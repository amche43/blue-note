import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'domain.dart';
import 'question_photos.dart';

/// Versioned vector actions. Erasing one action also erases its attached note.
class InkElement {
  final String id, kind, text, note, image;
  final List<Offset> points;
  final Rect box;
  final int color, rows, columns;
  final double width;
  const InkElement({
    required this.id,
    required this.kind,
    this.points = const [],
    this.box = Rect.zero,
    this.color = 0xff172952,
    this.width = 3,
    this.text = '',
    this.note = '',
    this.image = '',
    this.rows = 3,
    this.columns = 3,
  });
  bool get ink => kind == 'pen' || kind == 'highlight';
  Rect get bounds {
    if (!ink) return box;
    if (points.isEmpty) return Rect.zero;
    var r = Rect.fromPoints(points.first, points.first);
    for (final p in points.skip(1)) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.inflate(width / 2);
  }

  InkElement change({Offset? move, String? text, String? note}) => InkElement(
    id: id,
    kind: kind,
    points: move == null ? points : points.map((p) => p + move).toList(),
    box: move == null ? box : box.shift(move),
    color: color,
    width: width,
    text: text ?? this.text,
    note: note ?? this.note,
    image: image,
    rows: rows,
    columns: columns,
  );
  bool hit(Offset p, double radius) {
    if (!ink) return bounds.inflate(radius).contains(p);
    if (points.length == 1) {
      return (p - points.first).distance <= radius + width / 2;
    }
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], d = points[i] - a;
      final t = d.distanceSquared == 0
          ? 0.0
          : (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared).clamp(
              0.0,
              1.0,
            );
      if ((p - (a + d * t)).distance <= radius + width / 2) return true;
    }
    return false;
  }

  Json toJson() => {
    'id': id,
    'kind': kind,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'box': [box.left, box.top, box.width, box.height],
    'color': color,
    'width': width,
    'text': text,
    'note': note,
    'image': image,
    'rows': rows,
    'columns': columns,
  };
  static InkElement read(Object? raw) {
    if (raw is! Json) throw const FormatException('画布对象格式无效');
    double number(Object? v, double min, double max) {
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw const FormatException('画布坐标无效');
      }
      return v.toDouble();
    }

    String str(String k, int max) {
      final s = raw[k];
      if (s is! String || s.length > max) throw const FormatException('画布文字无效');
      return s;
    }

    final kind = str('kind', 16);
    if (![
      'pen',
      'highlight',
      'text',
      'image',
      'rect',
      'ellipse',
      'line',
      'table',
    ].contains(kind)) {
      throw const FormatException('不支持的画布对象');
    }
    final points = raw['points'], b = raw['box'];
    if (points is! List ||
        points.length > 12000 ||
        b is! List ||
        b.length != 4) {
      throw const FormatException('画布笔迹过大');
    }
    final result = InkElement(
      id: str('id', 80),
      kind: kind,
      points: points.map((p) {
        if (p is! List || p.length != 2) throw const FormatException('笔迹坐标无效');
        return Offset(number(p[0], -20000, 20000), number(p[1], -20000, 20000));
      }).toList(),
      box: Rect.fromLTWH(
        number(b[0], -20000, 20000),
        number(b[1], -20000, 20000),
        number(b[2], 0, 20000),
        number(b[3], 0, 20000),
      ),
      color: number(raw['color'], 0, 0xffffffff).toInt(),
      width: number(raw['width'], 1, 80),
      text: str('text', 18000),
      note: str('note', 4000),
      image: str('image', photoLimit),
      rows: number(raw['rows'], 1, 20).toInt(),
      columns: number(raw['columns'], 1, 20).toInt(),
    );
    if (result.ink && result.points.isEmpty) {
      throw const FormatException('笔迹不能为空');
    }
    if (kind == 'image') {
      if (result.image.isEmpty) throw const FormatException('画布照片不能为空');
      validatePhoto(result.image);
    }
    if (kind == 'text' && result.text.trim().isEmpty) {
      throw const FormatException('文字不能为空');
    }
    return result;
  }
}

class InkDocument {
  final List<InkElement> elements;
  final double height;
  final bool ruled;
  static const double pageWidth = 1000;
  const InkDocument({
    this.elements = const [],
    this.height = 1600,
    this.ruled = true,
  });
  InkDocument withElements(List<InkElement> value) => InkDocument(
    elements: List.unmodifiable(value),
    height: height,
    ruled: ruled,
  );
  String encode() => jsonEncode({
    'version': 1,
    'height': height,
    'ruled': ruled,
    'elements': elements.map((e) => e.toJson()).toList(),
  });
  static InkDocument decode(String raw) {
    if (raw.isEmpty) return const InkDocument();
    if (raw.length > 8 * 1024 * 1024) {
      throw const FormatException('画布超过 8MB，请分成多道题');
    }
    final j = jsonDecode(raw);
    if (j is! Json ||
        j['version'] != 1 ||
        j['ruled'] is! bool ||
        j['height'] is! num ||
        !(j['height'] as num).isFinite ||
        j['height'] < 400 ||
        j['height'] > 20000 ||
        j['elements'] is! List ||
        (j['elements'] as List).length > 3000) {
      throw const FormatException('画布格式无效');
    }
    final es = (j['elements'] as List).map(InkElement.read).toList();
    if (es.map((e) => e.id).toSet().length != es.length) {
      throw const FormatException('画布动作编号重复');
    }
    return InkDocument(
      elements: es,
      height: (j['height'] as num).toDouble(),
      ruled: j['ruled'] as bool,
    );
  }

  /// A swipe of the eraser is one undoable command; photos and text are selected/deleted separately.
  InkDocument erase(List<Offset> trail, double radius) {
    final samples = <Offset>[];
    for (var i = 0; i < trail.length; i++) {
      if (i == 0) {
        samples.add(trail[i]);
        continue;
      }
      final d = trail[i] - trail[i - 1];
      final steps = (d.distance / math.max(1, radius)).ceil().clamp(1, 2000);
      for (var n = 1; n <= steps; n++) {
        samples.add(trail[i - 1] + d * (n / steps));
      }
    }
    return withElements(
      elements
          .where(
            (e) =>
                ![
                  'pen',
                  'highlight',
                  'rect',
                  'ellipse',
                  'line',
                ].contains(e.kind) ||
                !samples.any((p) => e.hit(p, radius)),
          )
          .toList(),
    );
  }

  InkDocument insertSpace(double y, double amount) => InkDocument(
    height: math.min(20000, height + amount),
    ruled: ruled,
    elements: elements
        .map((e) => e.bounds.top >= y ? e.change(move: Offset(0, amount)) : e)
        .toList(),
  );
}

class InkHistory {
  InkDocument document;
  final List<InkDocument> undoStack = [], redoStack = [];
  InkHistory(this.document);
  void commit(InkDocument next) {
    undoStack.add(document);
    if (undoStack.length > 60) undoStack.removeAt(0);
    redoStack.clear();
    document = next;
  }

  void undo() {
    if (undoStack.isEmpty) return;
    redoStack.add(document);
    document = undoStack.removeLast();
  }

  void redo() {
    if (redoStack.isEmpty) return;
    undoStack.add(document);
    document = redoStack.removeLast();
  }
}
