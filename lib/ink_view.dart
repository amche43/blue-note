import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'ink_document.dart';

class InkPainter extends CustomPainter {
  final InkDocument document;
  final Map<String, ui.Image> images;
  final InkElement? pending;
  final Rect? selection;
  final bool paper;
  final String? fontFamily;
  InkPainter(
    this.document,
    this.images, {
    this.pending,
    this.selection,
    this.paper = true,
    this.fontFamily,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (paper) {
      canvas.drawColor(Colors.white, BlendMode.srcOver);
      if (document.ruled) {
        final p = Paint()
          ..color = const Color(0xffe9f0fa)
          ..strokeWidth = 1;
        for (double y = 48; y < size.height; y += 40) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      }
    }
    for (final e in [...document.elements, ?pending]) {
      drawElement(canvas, e);
    }
    if (selection != null) {
      canvas.drawRect(selection!, Paint()..color = const Color(0x222878f0));
      canvas.drawRect(
        selection!,
        Paint()
          ..color = const Color(0xff2878f0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  void label(Canvas c, String text, Rect rect, double font, Color color) {
    if (rect.width <= 0 || rect.height <= 0) return;
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: font,
          color: color,
          height: 1.45,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    c.save();
    c.clipRect(rect);
    p.paint(c, rect.topLeft);
    c.restore();
    p.dispose();
  }

  void drawElement(Canvas c, InkElement e) {
    final p = Paint()
      ..color = Color(e.color)
      ..strokeWidth = e.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (e.ink) {
      if (e.points.isEmpty) return;
      if ((e.kind == 'highlight' || e.kind == 'annotation')) {
        p.color = Color(e.color).withValues(alpha: .30);
      }
      final path = Path()..moveTo(e.points.first.dx, e.points.first.dy);
      for (final point in e.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (e.points.length == 1) {
        c.drawCircle(
          e.points.first,
          e.width / 2,
          p..style = PaintingStyle.fill,
        );
      } else {
        c.drawPath(path, p);
      }
      if (e.kind == 'annotation' || e.note.isNotEmpty) {
        final center = e.points.last;
        c.drawCircle(center, 12, Paint()..color = const Color(0xff2878f0));
        c.drawLine(
          center + const Offset(0, -5),
          center + const Offset(0, 2),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        c.drawCircle(
          center + const Offset(0, 6),
          1.3,
          Paint()..color = Colors.white,
        );
      }
    } else if (e.kind == 'image') {
      final img = images[e.image];
      if (img != null) {
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Alignment.topLeft.inscribe(
            applyBoxFit(
              BoxFit.contain,
              Size(img.width.toDouble(), img.height.toDouble()),
              e.box.size,
            ).destination,
            e.box,
          ),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else {
        label(c, '图片载入中…', e.box, 20, Colors.blueGrey);
      }
    } else if (e.kind == 'text') {
      label(c, e.text, e.box, e.width, Color(e.color));
    } else if (e.kind == 'rect') {
      c.drawRect(e.box, p);
    } else if (e.kind == 'ellipse') {
      c.drawOval(e.box, p);
    } else if (e.kind == 'line') {
      if (e.points.length == 2) {
        c.drawLine(e.points[0], e.points[1], p);
      } else {
        c.drawLine(e.box.topLeft, e.box.bottomRight, p);
      }
    } else if (e.kind == 'table') {
      final w = e.box.width / e.columns, h = e.box.height / e.rows;
      for (var r = 0; r <= e.rows; r++) {
        c.drawLine(
          e.box.topLeft + Offset(0, h * r),
          e.box.topRight + Offset(0, h * r),
          p,
        );
      }
      for (var col = 0; col <= e.columns; col++) {
        c.drawLine(
          e.box.topLeft + Offset(w * col, 0),
          e.box.bottomLeft + Offset(w * col, 0),
          p,
        );
      }
      final lines = e.text.split('\n');
      for (var r = 0; r < e.rows; r++) {
        final cells = r < lines.length ? lines[r].split('|') : <String>[];
        for (var col = 0; col < e.columns; col++) {
          label(
            c,
            col < cells.length ? cells[col] : '',
            Rect.fromLTWH(
              e.box.left + col * w + 8,
              e.box.top + r * h + 8,
              w - 16,
              h - 16,
            ),
            28,
            Color(e.color),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter old) => true;
}

Future<ui.Image> decodeInkImage(String encoded) async {
  final codec = await ui.instantiateImageCodec(
    base64Decode(encoded),
    targetWidth: 1800,
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

class InkPreview extends StatefulWidget {
  final String raw;
  const InkPreview(this.raw, {super.key});
  @override
  State<InkPreview> createState() => _InkPreviewState();
}

class _InkPreviewState extends State<InkPreview> {
  InkDocument document = const InkDocument();
  final transform = TransformationController();
  bool fitted = false;
  String? openNote;
  final Map<String, ui.Image> images = {};
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant InkPreview old) {
    super.didUpdateWidget(old);
    if (old.raw != widget.raw) load();
  }

  Future<void> load() async {
    try {
      document = InkDocument.decode(widget.raw);
      for (final e in document.elements.where((e) => e.kind == 'image')) {
        if (images.containsKey(e.image)) continue;
        final image = await decodeInkImage(e.image);
        if (!mounted) {
          image.dispose();
          return;
        }
        images[e.image] = image;
      }
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) setState(() => error = '画布暂时无法读取，请保留原文件。');
    }
  }

  @override
  void dispose() {
    transform.dispose();
    for (final image in images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Text(error!);
    return SizedBox(
      height: 420,
      child: LayoutBuilder(
        builder: (context, c) {
          if (!fitted) {
            fitted = true;
            transform.value = Matrix4.diagonal3Values(
              c.maxWidth / document.width,
              c.maxWidth / document.width,
              1,
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                constrained: false,
                minScale: .2,
                maxScale: 4,
                transformationController: transform,
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTapUp: (d) {
                    final e = document.elements.reversed
                        .where(
                          (e) =>
                              e.points.isNotEmpty &&
                              (e.kind == 'annotation' || e.note.isNotEmpty) &&
                              (e.points.last - d.localPosition).distance <
                                  20 / transform.value.getMaxScaleOnAxis(),
                        )
                        .firstOrNull;
                    if (e != null) {
                      setState(() => openNote = openNote == e.id ? null : e.id);
                    }
                  },
                  child: SizedBox(
                    width: document.width,
                    height: document.height,
                    child: CustomPaint(
                      painter: InkPainter(
                        document,
                        images,
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.fontFamily,
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<Matrix4>(
                valueListenable: transform,
                builder: (_, matrix, child) {
                  final e = document.elements
                      .where((e) => e.id == openNote && e.points.isNotEmpty)
                      .firstOrNull;
                  if (e == null) return const SizedBox.shrink();
                  final p = MatrixUtils.transformPoint(matrix, e.points.last);
                  final width = c.maxWidth < 280 ? c.maxWidth - 16 : 260.0;
                  return Positioned(
                    left: (p.dx - width / 2).clamp(8.0, c.maxWidth - width - 8),
                    top: (p.dy + 16).clamp(8.0, 220.0),
                    width: width,
                    child: Material(
                      elevation: 5,
                      color: const Color(0xfff1f7ff),
                      borderRadius: BorderRadius.circular(18),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 190),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: Text('思路标记')),
                                  IconButton(
                                    tooltip: '收起思路',
                                    onPressed: () =>
                                        setState(() => openNote = null),
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                              Text(e.note.isEmpty ? '暂未填写思路' : e.note),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
