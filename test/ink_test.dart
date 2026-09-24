import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/ink_document.dart';
import 'package:blue_note/achievements.dart';
import 'package:blue_note/ink_page.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/chapter_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('Blank pages, six presets and atomic inline chapter rename', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: InkPage(
          store: store,
          notebookId: 'book-11111111111111111111111111111111',
          notebookTitle: '我的本',
          chapter: '新建章节1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.questions.length, 1);
    final entry = store.questions.values.single;
    expect(entry['title'], '新建知识页1');
    expect(InkDocument.decode(entry['canvas'] as String).ruled, isFalse);
    expect(find.byKey(const ValueKey('ink-tool-panel')), findsNothing);
    final before = tester.getTopLeft(find.byKey(const ValueKey('ink-canvas')));
    await tester.tap(find.byTooltip('普通笔'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ink-tool-panel')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('ink-canvas'))), before);
    expect(find.byType(Slider), findsNothing);
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(ValueKey('ink-size-$i')), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('ink-color-'),
      ),
      findsNWidgets(6),
    );
    await tester.tap(find.byTooltip('移动 / 缩放画布'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起工具选项'));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    await tester.dragFrom(before + const Offset(150, 120), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.getTranslation().x, closeTo(0, 1));
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterPage(
          store: store,
          book: 'book-11111111111111111111111111111111',
          title: '我的本',
          chapter: '新建章节1',
          openLesson: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chapter-title')),
      '极限与连续',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.questions.values.single['chapter'], '极限与连续');
    expect(notebookChapters(store, 'book-11111111111111111111111111111111'), [
      '极限与连续',
    ]);
    final creating = createChapter(
      tester.element(find.byType(ChapterPage)),
      store,
      'book-11111111111111111111111111111111',
      '我的本',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用默认名称'));
    await tester.pumpAndSettle();
    await creating;
    expect(
      notebookChapters(store, 'book-11111111111111111111111111111111'),
      contains('新建章节1'),
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await store.db.close();
    store.dispose();
  });
  test(
    'Stroke eraser intersects segments, removes attached notes, undo restores the entire action',
    () {
      const stroke = InkElement(
        id: 'one',
        kind: 'highlight',
        width: 20,
        note: '先判断无穷小阶数',
        points: [Offset(20, 20), Offset(200, 200)],
      );
      const other = InkElement(
        id: 'two',
        kind: 'pen',
        points: [Offset(400, 20), Offset(400, 200)],
      );
      final h = InkHistory(const InkDocument(elements: [stroke, other]));
      expect(h.document.erase([const Offset(25, 180)], 5).elements.length, 2);
      h.commit(h.document.erase([const Offset(110, 110)], 5));
      expect(h.document.elements.single.id, 'two');
      h.undo();
      expect(h.document.elements.first.note, '先判断无穷小阶数');
      h.redo();
      expect(h.document.elements.length, 1);
      h.undo();
      h.commit(h.document.insertSpace(10, 120));
      expect(h.document.elements.first.points.first, const Offset(20, 140));
      expect(h.redoStack, isEmpty);
      expect(
        InkDocument.decode(h.document.encode()).elements.first.note,
        stroke.note,
      );
      final invalid = jsonDecode(h.document.encode()) as Map<String, dynamic>;
      invalid['elements'][0]['points'] = [
        [double.infinity, 1],
      ];
      expect(
        () => InkElement.read(invalid['elements'][0]),
        throwsFormatException,
      );
    },
  );
  test(
    'Ink-only entries and chapter metadata survive full backup and sharing',
    () async {
      var s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final book = 'book-${'c' * 32}';
      await s.setting(
        'notebook:$book',
        jsonEncode({
          'title': '极限错题本',
          'kind': 'question',
          'chapters': ['第一章', '空章节'],
        }),
      );
      final raw = const InkDocument(
        elements: [
          InkElement(
            id: 'p',
            kind: 'pen',
            points: [Offset(10, 10), Offset(100, 100)],
          ),
        ],
      ).encode();
      final id = await s.saveQuestion({
        ...blankQuestion(),
        'notebookId': book,
        'notebookTitle': '极限错题本',
        'chapter': '第一章',
        'canvas': raw,
      });
      expect(s.questions[id]!['title'], '第1题');
      final pack = decodeQuestionPackage(
        encodeQuestionPackage(
          id,
          s.questions[id]!,
          consent: true,
          author: '蓝笔',
        ),
      );
      expect(pack['question']['canvas'], raw);
      final backup = await s.fullBackup();
      await s.db.close();
      s.dispose();
      s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await s.restoreFull(backup);
      expect(s.questions[id]!['canvas'], raw);
      expect(
        jsonDecode(s.settings['notebook:$book']!)['chapters'],
        contains('空章节'),
      );
      await s.db.close();
      s.dispose();
    },
  );
  test(
    'Meaningful canvas annotations count toward learning, bare strokes do not',
    () {
      const e = InkElement(
        id: 'one',
        kind: 'highlight',
        points: [Offset(1, 1), Offset(50, 50)],
        note: '先判断条件，再使用公式',
      );
      final q = {
        ...blankQuestion(),
        'canvas': const InkDocument(elements: [e]).encode(),
      };
      expect(validLearning(q), isTrue);
      expect(
        validLearning({
          ...q,
          'canvas': InkDocument(elements: [e.change(note: '')]).encode(),
        }),
        isFalse,
      );
      expect(validLearning({...q, 'deleted': true}), isFalse);
    },
  );
  testWidgets(
    'Stylus-only mode ignores finger drawing and preserves pen input',
    (tester) async {
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await s.setting('canvasStylusOnly', 'true');
      await tester.pumpWidget(MaterialApp(home: InkPage(store: s)));
      await tester.pumpAndSettle();
      final point =
          tester.getTopLeft(find.byKey(const ValueKey('ink-canvas'))) +
          const Offset(60, 80);
      await tester.dragFrom(point, const Offset(100, 50));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNull,
      );
      final pen = await tester.startGesture(
        point,
        kind: ui.PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(100, 50));
      await pen.up();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip(RegExp('已保存在本机|修改待保存，点击重试')));
      await tester.pumpAndSettle();
      expect(
        InkDocument.decode(
          s.questions.values.single['canvas'] as String,
        ).elements.length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Canvas drawing can be undone, redone, saved, reopened and annotated',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await tester.pumpWidget(MaterialApp(home: InkPage(store: s)));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('ink-canvas')),
      );
      await tester.dragFrom(
        origin + const Offset(80, 120),
        const Offset(180, 45),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('撤销'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('重做'));
      await tester.pump();
      await tester.tap(find.byTooltip(RegExp('已保存在本机|修改待保存，点击重试')));
      await tester.pumpAndSettle();
      expect(s.questions.length, 1);
      final id = s.questions.keys.single;
      expect(
        InkDocument.decode(
          s.questions[id]!['canvas'] as String,
        ).elements.single.kind,
        'pen',
      );
      await tester.tap(find.byTooltip('思路标记笔'));
      await tester.pump();
      await tester.tap(find.byTooltip('收起工具选项'));
      await tester.pump();
      await tester.dragFrom(
        origin + const Offset(100, 220),
        const Offset(200, 0),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('thought-input')),
        '这里先使用三阶展开',
      );
      await tester.tap(find.byTooltip('收起思路'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(RegExp('已保存在本机|修改待保存，点击重试')));
      await tester.pumpAndSettle();
      expect(
        InkDocument.decode(
          s.questions[id]!['canvas'] as String,
        ).elements.last.note,
        '这里先使用三阶展开',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: InkPage(store: s, id: id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ink-canvas')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Selection copies only visible pixels into another notebook and keeps source ink',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final book = 'book-${'d' * 32}', target = 'book-${'e' * 32}';
      await s.setting(
        'notebook:$book',
        jsonEncode({'title': '原学习本', 'kind': 'question'}),
      );
      await s.setting(
        'notebook:$target',
        jsonEncode({'title': '提问学习本', 'kind': 'question'}),
      );
      final raw = const InkDocument(
        elements: [
          InkElement(
            id: 'ink',
            kind: 'highlight',
            color: 0xff2878f0,
            width: 20,
            points: [Offset(50, 50), Offset(250, 150)],
            note: '只留在原题的私人说明',
          ),
        ],
      ).encode();
      final id = await s.saveQuestion({
        ...blankQuestion(),
        'title': '原题',
        'canvas': raw,
        'notebookId': book,
        'notebookTitle': '原学习本',
        'chapter': '第一章',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: InkPage(store: s, id: id),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('框选 / 点击思路标记'));
      await tester.pump();
      await tester.tap(find.byTooltip('收起工具选项'));
      await tester.pump();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('ink-canvas')),
      );
      await tester.dragFrom(
        origin + const Offset(20, 20),
        const Offset(280, 200),
      );
      await tester.pump();
      await tester.runAsync(() => tester.tap(find.text('复制为新知识页')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提问学习本').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '局部题目');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '复制'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        if (s.questions.length == 2) break;
      }
      expect(s.questions.length, 2, reason: s.questions.toString());
      await tester.pump(const Duration(milliseconds: 500));
      final copied = s.questions.values.firstWhere((q) => q['title'] == '局部题目');
      expect(copied['notebookId'], target);
      final object = InkDocument.decode(
        copied['canvas'] as String,
      ).elements.single;
      expect(object.kind, 'image');
      expect(object.note, '');
      expect(copied['canvas'], isNot(contains('只留在原题的私人说明')));
      expect(s.questions[id]!['canvas'], raw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets('Phone and wide canvas layouts fit without overflow', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = FontLoader('Microsoft YaHei')
        ..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final doc = InkDocument(
      elements: [
        const InkElement(
          id: 't1',
          kind: 'text',
          text: '一道题，留住自己的思考',
          width: 48,
          box: Rect.fromLTWH(52, 65, 900, 85),
        ),
        const InkElement(
          id: 't2',
          kind: 'text',
          text:
              '求极限：lim (sin x − x) / x³，x → 0\n\n第一反应：连续求导，过程越来越复杂。\n\n关键一步：观察相消项，展开到三阶。',
          width: 34,
          box: Rect.fromLTWH(52, 185, 900, 350),
        ),
        const InkElement(
          id: 'h',
          kind: 'highlight',
          color: 0xfff9ca45,
          width: 32,
          points: [Offset(205, 411), Offset(805, 411)],
          note: '分子的一阶项相消，需要保留三阶项。',
        ),
        const InkElement(
          id: 't3',
          kind: 'text',
          text: 'sin x = x − x³ / 6 + o(x³)\n\n所以，原极限 = −1/6。',
          width: 36,
          color: 0xff2878f0,
          box: Rect.fromLTWH(52, 540, 900, 170),
        ),
        const InkElement(
          id: 'table',
          kind: 'table',
          rows: 3,
          columns: 2,
          width: 2,
          color: 0xff2878f0,
          text: '方法 | 观察\n泰勒展开 | 先找相消项\n洛必达法则 | 先检查适用条件',
          box: Rect.fromLTWH(52, 800, 860, 220),
        ),
      ],
    );
    final id = await s.saveQuestion({
      ...blankQuestion(),
      'title': '极限 · 先看相消项',
      'chapter': '第一章 函数极限',
      'canvas': doc.encode(),
    });
    for (final size in [const Size(390, 844), const Size(1200, 850)]) {
      tester.view.physicalSize = size;
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Microsoft YaHei',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff2878f0),
              ),
            ),
            home: InkPage(store: s, id: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '../../work/canvas23-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      final canvas = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('ink-canvas')),
      );
      await tester.tapAt(canvas.localToGlobal(const Offset(805, 411)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thought-bubble')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '../../work/canvas23-bubble-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.tapAt(canvas.localToGlobal(const Offset(805, 411)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thought-bubble')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    await s.db.close();
    s.dispose();
  });
}
