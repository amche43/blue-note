import 'learning_time.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'store.dart';
import 'questions.dart';
import 'ink_document.dart';
import 'ink_view.dart';
import 'editor_draft.dart';
import 'photo_import.dart';
import 'community.dart';

/// Local vector notebook page. Network publication remains an explicit action.
class InkPage extends StatefulWidget {
  final StudyStore store;
  final String? id, notebookId, notebookTitle, chapter, draftKey;
  final Json? initial;
  const InkPage({
    super.key,
    required this.store,
    this.id,
    this.notebookId,
    this.notebookTitle,
    this.chapter,
    this.initial,
    this.draftKey,
  });
  @override
  State<InkPage> createState() => _InkPageState();
}

class _InkPageState extends State<InkPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Timer? autoSave;
  late final LearningClock learningClock;
  Future<bool>? saving;
  final titleFocus = FocusNode();
  String defaultTitle = '新建页面1';
  double? elasticRawX, elasticShownX;
  late Json question;
  Json? expected, capture;
  late InkHistory history;
  late EditorDraft draft;
  final transform = TransformationController();
  final Map<String, ui.Image> images = {};
  final title = TextEditingController();
  final noteInput = TextEditingController();
  String? openNote;
  bool noteUndoStarted = false;
  late final AnimationController rebound;
  Matrix4? reboundFrom, reboundTo;
  Size viewport = Size.zero;

  String tool = 'pen', shape = 'rect', error = '';
  double penSize = 3, markerSize = 24, eraserSize = 22, textSize = 38;
  final colors = <String, int>{
    'pen': 0xff2878f0,
    'highlight': 0xfff9ca45,
    'annotation': 0xff46bda5,
    'table': 0xff2878f0,
  };
  int get color => colors[tool] ?? 0xff172952;
  set color(int value) => colors[tool] = value;
  int rows = 3, columns = 3;
  bool panelOpen = false,
      busy = false,
      ready = false,
      allowPop = false,
      fitted = false;
  String? savedId;
  bool stylusOnly = false;
  Offset? start;
  int? pointer;
  List<Offset> trail = [];
  InkElement? pending;
  Rect? selection;
  Set<String> selected = {};
  InkDocument get doc => history.document;

  @override
  void initState() {
    super.initState();
    learningClock = LearningClock(widget.store);
    WidgetsBinding.instance.addObserver(this);
    rebound =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 650),
        )..addListener(() {
          if (reboundFrom == null || reboundTo == null) return;
          final t = Curves.easeOutCubic.transform(rebound.value);
          transform.value = Matrix4Tween(
            begin: reboundFrom,
            end: reboundTo,
          ).lerp(t);
        });

    stylusOnly = widget.store.settings['canvasStylusOnly'] == 'true';
    expected = widget.id == null ? null : widget.store.questions[widget.id];
    question = {...blankQuestion(), ...?expected, ...?widget.initial};
    if (expected?['deleted'] == true) error = '这条题目已删除，请从历史记录恢复后编辑。';
    if (widget.notebookId != null) {
      question['notebookId'] = widget.notebookId;
      question['notebookTitle'] = widget.notebookTitle ?? '';
      question['chapter'] = widget.chapter ?? '';
      final meta = widget.store.settings['notebook:${widget.notebookId}'];
      if (meta != null) {
        question['contentKind'] =
            (jsonDecode(meta) as Json)['kind'] ?? 'question';
      }
    }
    title.text = question['title'] as String;
    if (title.text.trim().isEmpty) {
      final names = widget.store.questions.values
          .map((q) => q['title'])
          .toSet();
      var n = 1;
      while (names.contains('新建页面$n')) {
        n++;
      }
      title.text = '新建页面$n';
    }
    defaultTitle = title.text;
    history = InkHistory(const InkDocument());
    try {
      if (error.isEmpty) history = InkHistory(seed(question));
    } catch (e) {
      error = '画布无法读取，未修改原记录：$e';
    }
    savedId = widget.id;
    final key =
        widget.draftKey ??
        'editDraft:canvas-${widget.id ?? 'new-${widget.notebookId ?? ''}-${widget.chapter ?? ''}'}';
    draft = EditorDraft(
      widget.store,
      key,
      () => {
        'fields': {
          for (final e in {
            ...question,
            'title': title.text,
            'canvas': doc.encode(),
          }.entries)
            if (e.value is String) e.key: e.value,
        },
        'base': expected,
        'id': savedId,
        'capture': capture,
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (error.isNotEmpty) return;
      try {
        final journal = widget.store.settings[draft.key];
        if (journal != null) {
          final j = (jsonDecode(journal) as Json)['data'] as Json;
          question = {...blankQuestion(), ...(j['fields'] as Json)};
          expected = j['base'] as Json?;
          savedId = j['id'] as String?;
          capture = j['capture'] as Json?;
          title.text = question['title'] as String;
          history = InkHistory(
            InkDocument.decode(question['canvas'] as String),
          );
          draft.hasChanges = true;
        }
        draft.active = true;
        await loadImages();
        if (savedId != null && !draft.hasChanges) draft.status = '已保存到笔记本';
        if (mounted) {
          setState(() => ready = true);
          if (savedId == null || draft.hasChanges) await save();
          if (mounted && widget.id == null) {
            title.selection = TextSelection(
              baseOffset: 0,
              extentOffset: title.text.length,
            );
            titleFocus.requestFocus();
          }
        }
      } catch (e) {
        if (mounted) setState(() => error = '未能恢复上次内容，原记录保留：$e');
      }
    });
  }

  InkDocument seed(Json q) {
    if ((q['canvas'] as String? ?? '').isNotEmpty) {
      return InkDocument.decode(q['canvas'] as String);
    }
    final es = <InkElement>[];
    double y = 50;
    for (final k in [
      'prompt',
      'formula',
      'questionPhoto',
      'answer',
      'answerPhoto',
      'trigger',
      'action',
      'conditions',
      'pitfall',
      'firstThought',
      'errorReason',
      'summary',
    ]) {
      final value = q[k] as String? ?? '';
      if (value.isEmpty) continue;
      if (k.endsWith('Photo')) {
        es.add(
          InkElement(
            id: newId(),
            kind: 'image',
            image: value,
            box: Rect.fromLTWH(48, y, 900, 600),
          ),
        );
        y += 640;
      } else {
        const names = {
          'answer': '解答',
          'trigger': '关键突破',
          'action': '解题思路',
          'pitfall': '易错点',
          'firstThought': '我的理解',
          'summary': '总结',
        };
        final text = names.containsKey(k) ? '${names[k]}\n$value' : value;
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: 24, height: 1.45),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 900);
        final h = painter.height + 20;
        painter.dispose();
        es.add(
          InkElement(
            id: newId(),
            kind: 'text',
            text: text,
            width: 24,
            box: Rect.fromLTWH(48, y, 900, h),
          ),
        );
        y += h + 30;
      }
    }
    return InkDocument(
      elements: es,
      height: math.max(1600, math.min(20000, y + 400)),
    );
  }

  Future<void> loadImages() async {
    for (final e in doc.elements.where((e) => e.kind == 'image')) {
      if (images.containsKey(e.image)) continue;
      final img = await decodeInkImage(e.image);
      if (!mounted) {
        img.dispose();
        return;
      }
      images[e.image] = img;
    }
    if (mounted) setState(() {});
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  void commit(InkDocument next) {
    if (!ready || busy) return;
    try {
      InkDocument.decode(next.encode());
    } catch (e) {
      message('$e');
      return;
    }
    setState(() => history.commit(next));
    changed();
  }

  Future<T?> inputDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    required Iterable<TextEditingController> controllers,
  }) {
    final route = DialogRoute<T>(context: context, builder: builder);
    final result = Navigator.of(context).push(route);
    route.completed.then((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    return result;
  }

  Future<String?> ask(
    String heading, {
    String value = '',
    int max = 4000,
    bool multiline = true,
  }) async {
    final c = TextEditingController(text: value);
    final result = await inputDialog<String>(
      controllers: [c],
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(heading),
        content: TextField(
          autofocus: true,
          controller: c,
          maxLength: max,
          maxLines: multiline ? 7 : 1,
          decoration: const InputDecoration(hintText: '写下你的内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result;
  }

  void changed() {
    learningClock.touch();
    draft.schedule();
    if (mounted) setState(() {});
    autoSave?.cancel();
    autoSave = Timer(const Duration(milliseconds: 900), () {
      if (mounted && ready && !busy && pointer == null && draft.hasChanges) {
        save();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    learningClock.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (ready && draft.hasChanges && pointer == null) save();
    }
  }

  Future<bool> save() {
    if (saving != null) return saving!;
    final task = saveNow();
    saving = task;
    task.whenComplete(() => saving = null);
    return task;
  }

  Future<bool> saveNow() async {
    if (!ready || busy) return false;
    setState(() => busy = true);
    draft.active = false;
    try {
      await draft.settle();
      final q = {
        ...question,
        'title': title.text.trim().isEmpty ? defaultTitle : title.text.trim(),
        'canvas': doc.encode(),
        // Photos migrated onto the canvas remain there; avoid duplicating large image payloads.
        'questionPhoto': '', 'answerPhoto': '',
        for (final k in [
          'prompt',
          'formula',
          'answer',
          'trigger',
          'action',
          'conditions',
          'pitfall',
          'firstThought',
          'errorReason',
          'summary',
        ])
          k: '',
      };
      savedId = await widget.store.saveQuestion(
        q,
        id: savedId,
        expected: expected,
        capture: capture,
        clearDraftKey: draft.key,
      );
      expected = widget.store.questions[savedId]!;
      question = {...expected!};
      title.text = question['title'] as String;
      draft.hasChanges = false;
      draft.status = '已保存到笔记本';

      return true;
    } catch (e) {
      message('保存未完成：$e');
      return false;
    } finally {
      draft.active = true;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    autoSave?.cancel();
    await learningClock.writes;
    if (saving != null && !await saving!) return;
    if (draft.hasChanges && !await save()) return;
    if (mounted) {
      setState(() => allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, savedId);
    }
  }

  @override
  void dispose() {
    autoSave?.cancel();
    learningClock.close();
    WidgetsBinding.instance.removeObserver(this);
    titleFocus.dispose();
    draft.dispose();
    rebound.dispose();
    noteInput.dispose();
    transform.dispose();
    title.dispose();
    for (final image in images.values) {
      image.dispose();
    }
    super.dispose();
  }

  Offset clampPoint(Offset p) {
    if ([
      'pen',
      'highlight',
      'annotation',
      'shape',
      'table',
      'text',
    ].contains(tool)) {
      final width = p.dx >= doc.width - 80
          ? math.min(20000.0, math.max(doc.width + 500, p.dx + 200))
          : doc.width;
      final height = p.dy >= doc.height - 120
          ? math.min(20000.0, math.max(doc.height + 700, p.dy + 300))
          : doc.height;
      if (width != doc.width || height != doc.height) {
        history.document = InkDocument(
          elements: doc.elements,
          width: width,
          height: height,
          ruled: doc.ruled,
        );
      }
    }
    return Offset(p.dx.clamp(0.0, doc.width), p.dy.clamp(0.0, doc.height));
  }

  void down(PointerDownEvent event) {
    learningClock.touch();
    if (!ready || busy || pointer != null) return;
    final hit = doc.elements.reversed
        .where(
          (e) =>
              (e.kind == 'annotation' || e.note.isNotEmpty) &&
              e.points.isNotEmpty &&
              (e.points.last - event.localPosition).distance <=
                  18 / transform.value.getMaxScaleOnAxis(),
        )
        .firstOrNull;
    if (hit != null && tool != 'eraser') {
      toggleNote(hit);
      return;
    }
    if (tool == 'hand') return;
    if (panelOpen) setState(() => panelOpen = false);
    if (openNote != null) setState(() => openNote = null);

    if (stylusOnly &&
        ['pen', 'highlight', 'annotation', 'eraser'].contains(tool) &&
        event.kind != ui.PointerDeviceKind.stylus &&
        event.kind != ui.PointerDeviceKind.invertedStylus) {
      return;
    }
    pointer = event.pointer;
    start = clampPoint(event.localPosition);
    trail = [start!];
    if (tool == 'pen' || tool == 'highlight' || tool == 'annotation') {
      updateStroke();
    }
    if (tool == 'select') {
      setState(() => selection = Rect.fromPoints(start!, start!));
    }
  }

  void move(PointerMoveEvent event) {
    learningClock.touch();
    if (pointer != event.pointer || start == null) return;
    final p = clampPoint(event.localPosition);
    if (trail.length < 12000 && (p - trail.last).distance > .5) trail.add(p);
    if (tool == 'pen' || tool == 'highlight' || tool == 'annotation') {
      updateStroke();
    } else if (tool == 'eraser') {
      setState(() {});
    } else if (tool == 'select') {
      setState(() => selection = Rect.fromPoints(start!, p));
    } else if (tool == 'shape' || tool == 'table') {
      setState(
        () => pending = InkElement(
          id: 'pending',
          kind: tool == 'shape' ? shape : 'table',
          box: Rect.fromPoints(start!, p),
          points: shape == 'line' ? [start!, p] : const [],
          color: color,
          width: penSize,
          rows: rows,
          columns: columns,
        ),
      );
    }
  }

  void updateStroke() {
    setState(
      () => pending = InkElement(
        id: 'pending',
        kind: tool,
        points: List.of(trail),
        color: color,
        width: tool == 'pen' ? penSize : markerSize,
      ),
    );
  }

  Future<void> up(PointerUpEvent event) async {
    if (pointer != event.pointer || start == null) return;
    final p = start!;
    final action = pending;
    final path = List<Offset>.of(trail);
    setState(() {
      pointer = null;
      start = null;
      pending = null;
    });
    if (tool == 'eraser') {
      commit(doc.erase(path, eraserSize));
      return;
    }
    if (tool == 'space') {
      if (doc.height <= 19880) {
        commit(doc.insertSpace(p.dy, 120));
      } else {
        message('页面已到最大高度，请新建一页');
      }
      return;
    }
    if (tool == 'text') {
      await addText(p);
      return;
    }
    if (tool == 'select') {
      if ((selection?.longestSide ?? 0) < 12) {
        final e = doc.elements.reversed.where((e) => e.hit(p, 18)).firstOrNull;
        setState(() {
          selected = e == null ? {} : {e.id};
          selection = e?.bounds.inflate(8);
        });
        if (e != null && e.note.isNotEmpty) await editNote(e);
      } else {
        setState(
          () => selected = doc.elements
              .where((e) => e.bounds.overlaps(selection!))
              .map((e) => e.id)
              .toSet(),
        );
      }
      setState(() => panelOpen = selected.isNotEmpty);
      return;
    }
    if (action == null) return;
    if (!action.ink &&
        (action.box.width < 5 || action.box.height < 5) &&
        action.kind != 'line') {
      return;
    }
    const note = '';
    final e = InkElement(
      id: newId(),
      kind: action.kind,
      points: action.points,
      box: action.box,
      color: action.color,
      width: action.width,
      note: note,
      rows: rows,
      columns: columns,
    );
    commit(doc.withElements([...doc.elements, e]));
    if (e.kind == 'annotation') toggleNote(e);
  }

  void toggleNote(InkElement e) {
    setState(() {
      if (openNote == e.id) {
        openNote = null;
        FocusManager.instance.primaryFocus?.unfocus();
      } else {
        openNote = e.id;
        noteInput.text = e.note;
        noteUndoStarted = false;
      }
      panelOpen = false;
    });
  }

  Future<void> editNote(InkElement e) async => toggleNote(e);
  void updateNote(String value) {
    if (openNote == null || busy) return;
    if (!noteUndoStarted) {
      history.commit(doc);
      noteUndoStarted = true;
    }
    setState(
      () => history.document = doc.withElements(
        doc.elements
            .map((e) => e.id == openNote ? e.change(note: value) : e)
            .toList(),
      ),
    );
    changed();
  }

  InkElement textElement(
    String text,
    Offset p, {
    String? id,
    double? fontSize,
    int? textColor,
  }) {
    final w = math.max(120.0, math.min(800.0, 980 - p.dx));
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize ?? textSize, height: 1.45),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    final h = painter.height + 20;
    painter.dispose();
    return InkElement(
      id: id ?? newId(),
      kind: 'text',
      text: text,
      color: textColor ?? color,
      width: fontSize ?? textSize,
      box: Rect.fromLTWH(math.min(p.dx, 860), p.dy, w, h),
    );
  }

  Future<void> addText(Offset p) async {
    final text = await ask('插入文字', max: 18000);
    if (text == null || text.trim().isEmpty) return;
    final e = textElement(text, p);
    addElement(e);
  }

  void addElement(InkElement e) {
    if (e.bounds.bottom > 20000) {
      message('页面已满，请新建题目');
      return;
    }
    commit(
      InkDocument(
        elements: [...doc.elements, e],
        width: math.max(doc.width, e.bounds.right + 80).clamp(1000, 20000),
        height: math.max(doc.height, e.bounds.bottom + 60).clamp(400, 20000),
        ruled: doc.ruled,
      ),
    );
  }

  Future<void> photo() async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => PhotoImportPage(store: widget.store)),
    );
    if (result == null || !mounted) return;
    final point = transform.toScene(const Offset(36, 60));
    final p = Offset(48, math.max(40, point.dy));
    try {
      if ((result['photo'] as String? ?? '').isNotEmpty) {
        final encoded = result['photo'] as String;
        final img = await decodeInkImage(encoded);
        if (!mounted) {
          img.dispose();
          return;
        }
        images[encoded]?.dispose();
        images[encoded] = img;
        addElement(
          InkElement(
            id: newId(),
            kind: 'image',
            image: encoded,
            box: Rect.fromLTWH(p.dx, p.dy, 850, 850 * img.height / img.width),
          ),
        );
      } else {
        addElement(textElement(result['text'] as String? ?? '', p));
        capture = result['capture'] as Json?;
        changed();
      }
    } catch (e) {
      message('照片未插入：$e');
    }
  }

  Future<String?> editTable(InkElement e) async {
    final old = e.text.split('\n').map((line) => line.split('|')).toList();
    final cells = List.generate(
      e.rows,
      (r) => List.generate(
        e.columns,
        (col) => TextEditingController(
          text: r < old.length && col < old[r].length ? old[r][col].trim() : '',
        ),
      ),
    );
    final value = await inputDialog<String>(
      controllers: cells.expand((r) => r),
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑表格'),
        content: SizedBox(
          width: 600,
          height: math.min(400, e.rows * 70.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(260, e.columns * 160.0),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var r = 0; r < e.rows; r++)
                      Row(
                        children: [
                          for (var col = 0; col < e.columns; col++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: TextField(
                                  controller: cells[r][col],
                                  maxLength: 200,
                                  decoration: InputDecoration(
                                    hintText: '${r + 1}行 ${col + 1}列',
                                    counterText: '',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              cells
                  .map(
                    (row) => row
                        .map(
                          (c) =>
                              c.text.replaceAll('|', '｜').replaceAll('\n', ' '),
                        )
                        .join('|'),
                  )
                  .join('\n'),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<void> editSelected() async {
    final e = doc.elements.where((e) => selected.contains(e.id)).firstOrNull;
    if (e == null) return;
    if (e.kind == 'highlight' || e.kind == 'annotation') {
      await editNote(e);
      return;
    }
    if (e.kind == 'text' || e.kind == 'table') {
      final text = e.kind == 'table'
          ? await editTable(e)
          : await ask('编辑文字', value: e.text, max: 18000);
      if (text == null) return;
      final replacement = e.kind == 'text'
          ? textElement(
              text,
              e.box.topLeft,
              id: e.id,
              fontSize: e.width,
              textColor: e.color,
            )
          : e.change(text: text);
      commit(
        doc.withElements(
          doc.elements.map((v) => v.id == e.id ? replacement : v).toList(),
        ),
      );
    } else {
      message('可用方向按钮移动，删除键移除；图片可以框选后裁剪复制。');
    }
  }

  void shift(Offset delta) {
    if (selected.isEmpty) return;
    commit(
      doc.withElements(
        doc.elements
            .map((e) => selected.contains(e.id) ? e.change(move: delta) : e)
            .toList(),
      ),
    );
    setState(() => selection = selection?.shift(delta));
  }

  Future<void> location() async {
    if (!ready || busy) return;
    final books = <String, String>{'': '暂不归入笔记本'};
    for (final q in widget.store.questions.values) {
      if (q['deleted'] == false && q['notebookId'] != '') {
        books[q['notebookId'] as String] = q['notebookTitle'] as String;
      }
    }
    for (final e in widget.store.settings.entries.where(
      (e) => e.key.startsWith('notebook:'),
    )) {
      books[e.key.substring(9)] =
          (jsonDecode(e.value) as Json)['title'] as String;
    }
    String book = books.containsKey(question['notebookId'])
        ? question['notebookId'] as String
        : '';
    final chapter = TextEditingController(text: question['chapter'] as String);
    final subject = TextEditingController(text: question['subject'] as String);
    final yes = await inputDialog<bool>(
      controllers: [chapter, subject],
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('放进我的笔记本'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: book,
                  isExpanded: true,
                  items: books.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => set(() => book = v!),
                ),
                TextField(
                  controller: chapter,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '章节'),
                ),
                TextField(
                  controller: subject,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: '科目'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (subject.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      setState(() {
        if (book != question['notebookId']) question['questionNumber'] = '';
        question['notebookId'] = book;
        question['notebookTitle'] = book.isEmpty ? '' : books[book];
        question['chapter'] = chapter.text.trim();
        question['subject'] = subject.text.trim();
        final meta = widget.store.settings['notebook:$book'];
        if (meta != null) {
          question['contentKind'] =
              (jsonDecode(meta) as Json)['kind'] ?? 'question';
        }
      });
      changed();
    }
  }

  Future<void> copyRegion() async {
    final rect = selection?.intersect(
      Rect.fromLTWH(0, 0, doc.width, doc.height),
    );
    if (rect == null ||
        rect.width < 10 ||
        rect.height < 10 ||
        selected.isEmpty) {
      message('先框选要复制的区域');
      return;
    }
    final books = <String, String>{};
    for (final q in widget.store.questions.values) {
      if (q['deleted'] == false && q['notebookId'] != '') {
        books[q['notebookId'] as String] = q['notebookTitle'] as String;
      }
    }
    for (final e in widget.store.settings.entries.where(
      (e) => e.key.startsWith('notebook:'),
    )) {
      books[e.key.substring(9)] =
          (jsonDecode(e.value) as Json)['title'] as String;
    }
    if (books.isEmpty) {
      message('请先创建目标笔记本');
      return;
    }
    String book = books.containsKey(question['notebookId'])
        ? question['notebookId'] as String
        : books.keys.first;
    final chapter = TextEditingController(text: question['chapter'] as String),
        name = TextEditingController();
    final yes = await inputDialog<bool>(
      controllers: [chapter, name],
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('复制为新页面'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('只复制框内可见内容为照片，不包含隐藏思路文字；原题不变。新题可继续书写、单独上传社区。'),
                DropdownButtonFormField<String>(
                  initialValue: book,
                  isExpanded: true,
                  items: books.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => set(() => book = v!),
                ),
                TextField(
                  controller: chapter,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '目标章节（可新建）'),
                ),
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '题目标题（选填）'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('复制'),
            ),
          ],
        ),
      ),
    );
    final chapterName = chapter.text.trim(), titleName = name.text.trim();
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await loadImages();
      final recorder = ui.PictureRecorder(), c = Canvas(recorder);
      final scale = math.min(2.0, 2000 / math.max(rect.width, rect.height));
      c.scale(scale);
      c.translate(-rect.left, -rect.top);
      c.clipRect(rect);
      c.drawColor(Colors.white, BlendMode.srcOver);
      // Raster crop deliberately excludes hidden annotations and all pixels outside the selection.
      final cropped = doc.withElements(
        doc.elements.map((e) => e.change(note: '')).toList(),
      );
      InkPainter(
        cropped,
        images,
        paper: false,
      ).paint(c, Size(doc.width, doc.height));
      final picture = recorder.endRecording();
      final img = await picture.toImage(
        (rect.width * scale).ceil(),
        (rect.height * scale).ceil(),
      );
      picture.dispose();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) throw const FormatException('无法生成区域图片');
      final encoded = base64Encode(data.buffer.asUint8List());
      final newDoc = InkDocument(
        elements: [
          InkElement(
            id: newId(),
            kind: 'image',
            image: encoded,
            box: Rect.fromLTWH(
              40,
              40,
              math.min(920, rect.width),
              math.min(920, rect.width) * rect.height / rect.width,
            ),
          ),
        ],
        height: math.max(1600, math.min(20000, rect.height + 200)),
      );
      final id = await widget.store.saveQuestion({
        ...blankQuestion(),
        'title': titleName,
        'subject': question['subject'],
        'notebookId': book,
        'notebookTitle': books[book],
        'chapter': chapterName,
        'canvas': newDoc.encode(),
        'source': '从「${title.text.isEmpty ? '未命名题目' : title.text}」的选区复制',
      });
      message(
        '已复制到 ${books[book]} / ${chapterName.isEmpty ? '未分章' : chapterName}',
      );
      if (mounted) {
        await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => InkPage(store: widget.store, id: id),
          ),
        );
      }
    } catch (e) {
      message('复制未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget toolButton(String value, String label, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: IconButton.filledTonal(
      tooltip: label,
      isSelected: tool == value,
      style: IconButton.styleFrom(
        backgroundColor: tool == value
            ? const Color(0xffd7e8ff)
            : Colors.transparent,
      ),
      onPressed: !ready || busy
          ? null
          : () => setState(() {
              panelOpen = tool == value ? !panelOpen : true;
              openNote = null;
              tool = value;
              pending = null;
              start = null;
              pointer = null;
            }),
      icon: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        offset: tool == value ? const Offset(0, -.18) : Offset.zero,
        child: Icon(icon, size: 25),
      ),
    ),
  );
  Widget toolbar() => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              toolButton('hand', '移动 / 缩放画布', Icons.pan_tool_outlined),
              toolButton('pen', '普通笔', Icons.edit_outlined),
              toolButton('highlight', '荧光笔', Icons.border_color_outlined),
              toolButton('annotation', '思路标记笔', Icons.edit_note_rounded),
              toolButton('eraser', '整笔橡皮擦', Icons.auto_fix_normal),
              toolButton('text', '文字 · 点击画布插入', Icons.text_fields),
              toolButton('select', '框选 / 点击思路标记', Icons.select_all),
              toolButton('space', '插入空行 · 点击位置下移内容', Icons.unfold_more),
              toolButton('shape', '图形 · 拖动绘制', Icons.category_outlined),
              toolButton('table', '表格 · 拖动创建', Icons.table_chart_outlined),
              IconButton(
                tooltip: '照片 / 识字',
                onPressed: ready && !busy ? photo : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
            ],
          ),
        ),
      ),
      IconButton(
        tooltip: '撤销',
        onPressed: !busy && history.undoStack.isNotEmpty
            ? () {
                setState(() {
                  history.undo();
                  openNote = null;
                });
                changed();
              }
            : null,
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        tooltip: '重做',
        onPressed: !busy && history.redoStack.isNotEmpty
            ? () {
                setState(() {
                  history.redo();
                  openNote = null;
                });
                changed();
              }
            : null,
        icon: const Icon(Icons.redo),
      ),
    ],
  );
  List<double> get sizes => tool == 'eraser'
      ? [8, 14, 22, 34, 50, 70]
      : tool == 'text'
      ? [18, 24, 30, 38, 48, 60]
      : ['highlight', 'annotation'].contains(tool)
      ? [8, 14, 20, 24, 32, 40]
      : [1, 3, 5, 8, 12, 18];
  double get chosenSize => tool == 'eraser'
      ? eraserSize
      : tool == 'text'
      ? textSize
      : ['highlight', 'annotation'].contains(tool)
      ? markerSize
      : penSize;
  void setSize(double v) => setState(() {
    if (tool == 'eraser') {
      eraserSize = v;
    } else if (tool == 'text') {
      textSize = v;
    } else if (['highlight', 'annotation'].contains(tool)) {
      markerSize = v;
    } else {
      penSize = v;
    }
  });
  Widget options() => Material(
    key: const ValueKey('ink-tool-panel'),
    color: Colors.white,
    elevation: 8,
    shadowColor: const Color(0x332878f0),
    borderRadius: BorderRadius.circular(22),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  {
                    'pen': '普通笔',
                    'highlight': '荧光笔',
                    'annotation': '思路标记笔',
                    'eraser': '整笔橡皮擦',
                    'text': '文字',
                    'shape': '图形',
                    'table': '表格',
                    'select': '选择',
                    'hand': '移动画布',
                    'space': '插入空行',
                  }[tool]!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '收起工具选项',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => panelOpen = false),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if ([
            'pen',
            'highlight',
            'annotation',
            'shape',
            'text',
            'table',
          ].contains(tool))
            Wrap(
              children: [
                for (final c in [
                  0xff172952,
                  0xff2878f0,
                  0xfff9ca45,
                  0xffef668c,
                  0xff46bda5,
                  0xff9865d6,
                ])
                  IconButton(
                    key: ValueKey('ink-color-$c'),
                    tooltip: const {
                      0xff172952: '墨色',
                      0xff2878f0: '蓝色',
                      0xfff9ca45: '黄色',
                      0xffef668c: '粉红色',
                      0xff46bda5: '绿色',
                      0xff9865d6: '紫色',
                    }[c],
                    onPressed: () => setState(() => color = c),
                    icon: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == c ? Colors.black : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if ([
            'pen',
            'highlight',
            'annotation',
            'eraser',
            'shape',
            'text',
            'table',
          ].contains(tool)) ...[
            Text(
              tool == 'eraser'
                  ? '擦除范围'
                  : tool == 'text'
                  ? '字号'
                  : '笔迹大小',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            Wrap(
              spacing: 4,
              children: [
                for (var i = 0; i < 6; i++)
                  ChoiceChip(
                    key: ValueKey('ink-size-$i'),
                    label: Text('${i + 1}'),
                    selected: chosenSize == sizes[i],
                    showCheckmark: false,
                    onSelected: (_) => setSize(sizes[i]),
                  ),
              ],
            ),
          ],
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (tool == 'shape')
                DropdownButton<String>(
                  value: shape,
                  items: const [
                    DropdownMenuItem(value: 'rect', child: Text('矩形')),
                    DropdownMenuItem(value: 'ellipse', child: Text('椭圆')),
                    DropdownMenuItem(value: 'line', child: Text('直线')),
                  ],
                  onChanged: (v) => setState(() => shape = v!),
                ),
              if (tool == 'table') ...[
                const Text('行'),
                DropdownButton<int>(
                  value: rows,
                  items: [
                    for (var n = 1; n <= 8; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => setState(() => rows = v!),
                ),
                const Text('列'),
                DropdownButton<int>(
                  value: columns,
                  items: [
                    for (var n = 1; n <= 8; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => setState(() => columns = v!),
                ),
              ],
              if (tool == 'select') ...[
                TextButton.icon(
                  onPressed: selected.isEmpty ? null : editSelected,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: selected.isEmpty ? null : copyRegion,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制为新页面'),
                ),
                IconButton(
                  tooltip: '左移',
                  onPressed: () => shift(const Offset(-20, 0)),
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: '右移',
                  onPressed: () => shift(const Offset(20, 0)),
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: '上移',
                  onPressed: () => shift(const Offset(0, -20)),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: () => shift(const Offset(0, 20)),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: '删除选中动作（可撤销）',
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          commit(
                            doc.withElements(
                              doc.elements
                                  .where((e) => !selected.contains(e.id))
                                  .toList(),
                            ),
                          );
                          setState(() {
                            selected = {};
                            selection = null;
                          });
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
              if (tool == 'hand')
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('拖动移动 · 双指或触控板缩放'),
                ),
              if (tool == 'space')
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('点击后，下面的内容向下移动三行；可撤销'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  void settleBoundary() {
    if (viewport.isEmpty) return;
    final m = transform.value.clone(), scale = m.getMaxScaleOnAxis();
    final v = m.getTranslation();
    final x = v.x.clamp(math.min(0.0, viewport.width - doc.width * scale), 0.0);
    final y = v.y.clamp(
      math.min(0.0, viewport.height - doc.height * scale),
      0.0,
    );
    if ((v.x - x).abs() < .1 && (v.y - y).abs() < .1) return;
    reboundFrom = m;
    reboundTo = m.clone()..setTranslationRaw(x.toDouble(), y.toDouble(), 0);
    rebound.forward(from: 0);
  }

  Widget noteBubble(InkElement e, BoxConstraints c) {
    final anchor = MatrixUtils.transformPoint(transform.value, e.points.last);
    final measure = TextPainter(
      text: TextSpan(
        text: noteInput.text.isEmpty ? '点击填写你的思路' : noteInput.text,
        style: const TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 250);
    final width = math.min(
      c.maxWidth - 24,
      math.max(200.0, measure.width + 36),
    );
    measure.dispose();
    final number =
        doc.elements
            .where((v) => v.kind == 'annotation' || v.note.isNotEmpty)
            .toList()
            .indexWhere((v) => v.id == e.id) +
        1;
    return Positioned(
      left: anchor.dx.clamp(12.0, math.max(12.0, c.maxWidth - width - 12)),
      top: (anchor.dy + 20).clamp(8.0, math.max(8.0, c.maxHeight - 160)),
      width: width,
      child: Material(
        key: const ValueKey('thought-bubble'),
        elevation: 6,
        color: const Color(0xfff1f7ff),
        shadowColor: const Color(0x332878f0),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(5),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(80, math.min(260, c.maxHeight - 24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '新建思路$number',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff2878f0),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '收起思路',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => toggleNote(e),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('thought-input'),
                  controller: noteInput,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: null,
                  maxLength: 4000,
                  onChanged: updateNote,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: '点击填写你的思路',
                    counterText: '',
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget canvas() => LayoutBuilder(
    builder: (ctx, c) {
      viewport = Size(c.maxWidth, c.maxHeight);
      if (!fitted && c.maxWidth > 0) {
        fitted = true;
        transform.value = Matrix4.diagonal3Values(
          c.maxWidth / doc.width,
          c.maxWidth / doc.width,
          1,
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white,
                child: InteractiveViewer(
                  transformationController: transform,
                  constrained: false,
                  alignment: Alignment.topLeft,
                  minScale: c.maxWidth / doc.width,
                  maxScale: math.max(4, c.maxWidth / doc.width),
                  boundaryMargin: const EdgeInsets.all(90),
                  panEnabled: tool == 'hand',
                  scaleEnabled: tool == 'hand',
                  onInteractionStart: (_) {
                    learningClock.touch();
                    rebound.stop();
                    elasticRawX = null;
                    elasticShownX = null;
                  },
                  onInteractionUpdate: (_) {
                    final m = transform.value.clone();
                    final v = m.getTranslation();
                    if (v.x > 0) {
                      elasticRawX = math.max(
                        0.0,
                        (elasticRawX ?? v.x) +
                            (elasticShownX == null ? 0 : v.x - elasticShownX!),
                      );
                      final resisted = 100 * math.log(1 + elasticRawX! / 100);
                      elasticShownX = resisted;
                      transform.value = m..setTranslationRaw(resisted, v.y, 0);
                    } else {
                      elasticRawX = null;
                      elasticShownX = null;
                    }
                  },
                  onInteractionEnd: (_) => settleBoundary(),
                  child: Listener(
                    onPointerDown: down,
                    onPointerMove: move,
                    onPointerUp: up,
                    onPointerCancel: (_) => setState(() {
                      pointer = null;
                      start = null;
                      pending = null;
                    }),
                    child: SizedBox(
                      width: doc.width,
                      height: doc.height,
                      child: CustomPaint(
                        key: const ValueKey('ink-canvas'),
                        painter: InkPainter(
                          tool == 'eraser' && pointer != null
                              ? doc.erase(trail, eraserSize)
                              : doc,
                          images,
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.fontFamily,
                          pending: pending,
                          selection: tool == 'select' ? selection : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: transform,
              builder: (_, value, child) {
                final e = doc.elements
                    .where((e) => e.id == openNote && e.points.isNotEmpty)
                    .firstOrNull;
                return e == null ? const SizedBox.shrink() : noteBubble(e, c);
              },
            ),
            if (panelOpen)
              Positioned(
                left: 12,
                top: 8,
                width: math.min(320, c.maxWidth - 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(40, c.maxHeight - 16),
                  ),
                  child: SingleChildScrollView(child: options()),
                ),
              ),
          ],
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => PopScope<String>(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) leave();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          save();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (ready && !busy && history.undoStack.isNotEmpty) {
            setState(() {
              history.undo();
              openNote = null;
            });
            changed();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (ready && !busy && history.redoStack.isNotEmpty) {
            setState(() {
              history.redo();
              openNote = null;
            });
            changed();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xfff6f9ff),
          appBar: AppBar(
            leading: IconButton(
              tooltip: '返回',
              onPressed: leave,
              icon: const Icon(Icons.arrow_back),
            ),
            title: TextField(
              controller: title,
              focusNode: titleFocus,
              enabled: ready && !busy,
              maxLength: 120,
              onChanged: (_) => changed(),
              decoration: const InputDecoration(
                hintText: '题目标题（选填）',
                border: InputBorder.none,
                counterText: '',
              ),
            ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'stylus') {
                    setState(() => stylusOnly = !stylusOnly);
                    try {
                      await widget.store.setting(
                        'canvasStylusOnly',
                        stylusOnly.toString(),
                      );
                    } catch (_) {
                      message('本次输入模式已切换，偏好未能保存');
                    }
                  }
                  if (v == 'ruled') {
                    commit(
                      InkDocument(
                        elements: doc.elements,
                        height: doc.height,
                        width: doc.width,
                        ruled: !doc.ruled,
                      ),
                    );
                  }
                  if (v == 'extend') {
                    commit(
                      InkDocument(
                        elements: doc.elements,
                        height: math.min(20000, doc.height + 1000),
                        ruled: doc.ruled,
                      ),
                    );
                  }
                  if (v == 'location') await location();
                  if (v == 'fit') setState(() => fitted = false);
                  if (v == 'publish' && await save() && context.mounted) {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityPage(
                          store: widget.store,
                          initialQuestion: savedId,
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'stylus',
                    checked: stylusOnly,
                    child: const Text('仅手写笔绘制'),
                  ),
                  PopupMenuItem(
                    value: 'ruled',
                    child: Text(doc.ruled ? '隐藏横线' : '显示横线'),
                  ),
                  const PopupMenuItem(value: 'fit', child: Text('适合屏幕宽度')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${question['notebookTitle'] == '' ? '未归入笔记本' : question['notebookTitle']} / ${question['chapter'] == '' ? '未分章' : question['chapter']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                toolbar(),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Row(
                      children: [
                        if (c.maxWidth >= 950)
                          SizedBox(
                            width: 210,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                const Text(
                                  '这一章',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                for (final e
                                    in widget.store.questions.entries.where(
                                      (e) =>
                                          e.value['deleted'] == false &&
                                          e.value['notebookId'] ==
                                              question['notebookId'] &&
                                          e.value['chapter'] ==
                                              question['chapter'],
                                    ))
                                  ListTile(
                                    selected: e.key == savedId,
                                    dense: true,
                                    title: Text(e.value['title'] as String),
                                    onTap: () async {
                                      if (e.key == savedId) return;
                                      if (draft.hasChanges && !await save()) {
                                        return;
                                      }
                                      if (!context.mounted) return;
                                      await Navigator.push<String>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => InkPage(
                                            store: widget.store,
                                            id: e.key,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                const Divider(),
                                const Text(
                                  '点击笔迹末尾的圆圈，展开或收起思路气泡。点击工具可调整大小和颜色。',
                                  style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(child: canvas()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
