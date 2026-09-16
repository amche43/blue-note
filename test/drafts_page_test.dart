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
import 'package:blue_note/drafts_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'Draft box searches, restores the exact slot and deletes only confirmed drafts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final id = await s.saveQuestion({
        ...blankQuestion(),
        'title': '已保存的题目',
        'prompt': '完整题干',
      });
      await s.setting(
        'editDraft:composer-question',
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'data': {
            'fields': {'title': '极限计算的突破点', 'prompt': '我还要补充余项的理解'},
            'kind': 'question',
            'book': '',
            'step': 0,
            'capture': null,
          },
        }),
      );
      await s.setting(
        'editDraft:$id',
        jsonEncode({
            'at': DateTime.now().subtract(const Duration(hours:2)).millisecondsSinceEpoch,
          'data': {
            'base': s.questions[id],
            'fields': {
              for (final e in s.questions[id]!.entries)
                if (e.key != 'deleted') e.key: e.value,
            },
            'capture': null,
          },
        }),
      );
      await s.setting(
        'editDraft:composer-knowledge',
        jsonEncode({
            'at': DateTime.now().subtract(const Duration(hours:1)).millisecondsSinceEpoch,
          'data': {
            'fields': {'title': '熟知端口号', 'prompt': 'HTTP 与 HTTPS'},
            'kind': 'knowledge',
            'book': '',
            'step': 1,
            'capture': null,
          },
        }),
      );
      await tester.runAsync(() async {
        for (final item in [
          ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
          (
            'MaterialIcons',
            '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          final bytes = await File(item.$2).readAsBytes();
          await (FontLoader(
            item.$1,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: blueNoteTheme(),
            home: DraftsPage(store: s),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 份未完成的思考'), findsOneWidget);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../ui18-drafts.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('知识卡片'));
      await tester.pumpAndSettle();
      expect(find.text('熟知端口号'), findsOneWidget);
      expect(find.text('极限计算的突破点'), findsNothing);
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '余项');
      await tester.pumpAndSettle();
      expect(find.text('极限计算的突破点'), findsOneWidget);
      expect(find.text('熟知端口号'), findsNothing);
      await tester.tap(find.text('极限计算的突破点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      expect(find.text('极限计算的突破点'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并退出'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '已保存');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(s.settings.containsKey('editDraft:$id'), isTrue);
      await tester.tap(find.byTooltip('删除草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除草稿'));
      await tester.pumpAndSettle();
      expect(s.settings.containsKey('editDraft:$id'), isFalse);
      expect(s.questions[id]!['deleted'], isFalse);
      await tester.enterText(find.byType(TextField), '');
      await s.setting('editDraft:broken', 'bad-json');
      await tester.pumpAndSettle();
      await tester.tap(find.text('无法读取的草稿'));
      await tester.pumpAndSettle();
      expect(find.text('这份草稿暂时无法读取，未修改原记录。'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
