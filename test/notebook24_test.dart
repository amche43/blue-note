import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/notebooks.dart';
import 'package:blue_note/ink_page.dart';
import 'package:blue_note/ink_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'Notebook chapter knowledge hierarchy renders on phones and creates canvas pages',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final pair in [
          ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
          (
            'MaterialIcons',
            '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          if (await File(pair.$2).exists()) {
            final bytes = await File(pair.$2).readAsBytes();
            await (FontLoader(
              pair.$1,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
        }
      });
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      expect(s.lessons, isEmpty);
      expect(s.bundledLessons, isEmpty);
      final book = 'book-${'a' * 32}';
      await s.setting(
        'notebook:$book',
        jsonEncode({
          'title': '高数',
          'kind': 'question',
          'chapters': ['函数与极限', '一元函数微分学', '一元函数积分学'],
        }),
      );
      final id = await s.saveQuestion({
        ...blankQuestion(),
        'title': '泰勒公式',
        'prompt': '自己的旧版文字与推导',
        'notebookId': book,
        'notebookTitle': '高数',
        'chapter': '函数与极限',
      });
      final boundary = GlobalKey();
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File(
            '../../work/ui25-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      for (final width in [320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: blueNoteTheme(),
              home: AllNotebooksPage(store: s, openLesson: (_) async {}),
            ),
          ),
        );
        await shot('notebooks-${width.toInt()}');
        await tester.tap(find.text('高数'));
        await shot('chapters-${width.toInt()}');
        expect(find.byTooltip('新建章节'), findsOneWidget);
        await tester.tap(find.text('函数与极限'));
        await shot('pages-${width.toInt()}');
        expect(find.byTooltip('新建知识页'), findsOneWidget);
        expect(find.textContaining('协作者'), findsNothing);
        await tester.tap(find.text('泰勒公式'));
        await tester.pumpAndSettle();
        expect(find.byType(InkPage), findsOneWidget);
        await tester.tap(find.byTooltip(RegExp('已保存在本机|修改待保存，点击重试')));
        await tester.pumpAndSettle();
        expect(
          InkDocument.decode(
            s.questions[id]!['canvas'] as String,
          ).elements.any((e) => e.text.contains('自己的旧版文字与推导')),
          isTrue,
        );
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('新建知识页'));
        await tester.pumpAndSettle();
        expect(find.byType(InkPage), findsOneWidget);
        expect(
          s.questions.values.any(
            (q) => (q['title'] as String).startsWith('新建知识页'),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
