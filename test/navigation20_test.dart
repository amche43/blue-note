import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/daily_greeting.dart';
import 'package:blue_note/notebooks.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/swipe_delete.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Greeting is stable within date and changes at midnight', () {
    expect(
      greetingFor(DateTime(2026, 9, 17)),
      greetingFor(DateTime(2026, 9, 17, 23, 59)),
    );
    expect(
      greetingFor(DateTime(2026, 9, 18)),
      isNot(greetingFor(DateTime(2026, 9, 17))),
    );
  });
  testWidgets('Profile zero stats navigate and settings have focused groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final font in [
        ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        final bytes = await File(font.$2).readAsBytes();
        await (FontLoader(
          font.$1,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    final s = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: BlueNoteApp(store: s),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    for (final label in ['学习本', '知识卡片', '题目', '复习记录']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          {
            '学习本': '我的学习本',
            '知识卡片': '我的知识卡片',
            '题目': '我的题目',
            '复习记录': '共 0 条记录',
          }[label]!,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('设置'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('账号登录与注册'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSettingsPage), findsOneWidget);
    expect(find.text('我的学习成果'), findsNothing);
    expect(find.text('备份与恢复'), findsOneWidget);
    await tester.runAsync(() async {
      final picture =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../ui20-settings.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await s.db.close();
    s.dispose();
  });
  testWidgets(
    'Notebook swipe reveals delete, cancel preserves, confirm removes only that book',
    (tester) async {
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final a = 'book-${'a' * 32}', b = 'book-${'b' * 32}';
      await s.setting(
        'notebook:$a',
        jsonEncode({'title': '数学本', 'kind': 'question'}),
      );
      final q = await s.saveQuestion({
        ...blankQuestion(),
        'title': '极限',
        'prompt': '求极限',
        'notebookId': a,
        'notebookTitle': '数学本',
      });
      final other = await s.saveQuestion({
        ...blankQuestion(),
        'title': '端口',
        'prompt': '端口号',
        'notebookId': b,
        'notebookTitle': '网络本',
      });
      await s.setting('editDraft:kept', '{}');
      await tester.pumpWidget(
        MaterialApp(
          home: AllNotebooksPage(store: s, openLesson: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('数学本'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(s.questions[q]!['deleted'], false);
      final row = find.byKey(ValueKey(a));
      await tester.tap(find.descendant(of: row, matching: find.text('删除')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(notebooks(s).containsKey(a), true);
      await tester.drag(find.text('数学本'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: row, matching: find.text('删除')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();
      expect(notebooks(s).containsKey(a), false);
      expect(s.questions[q]!['deleted'], true);
      expect(s.questions[other]!['deleted'], false);
      expect(s.settings.containsKey('editDraft:kept'), true);
      expect(find.byType(SwipeDelete), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
