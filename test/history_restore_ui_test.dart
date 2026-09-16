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
import 'package:blue_note/question_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'History page restores explicitly selected field and retains every version',
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
        'title': '极限中的对称性',
        'prompt': '求极限',
        'answer': '先观察对称关系',
        'summary': '留意区间',
      });
      await s.saveQuestion({
        ...s.questions[id]!,
        'answer': '直接展开',
        'summary': '还要核对适用条件',
      }, id: id);
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
            home: QuestionEditor(store: s, id: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('原图、录入记录与修改历史'));await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('与当前对照 / 选择恢复'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '恢复所选 0 项'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('正确解法'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../ui19-history-restore.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('恢复所选 1 项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续核对'));
      await tester.pumpAndSettle();
      expect(s.events.length, 2);
      await tester.tap(find.text('恢复所选 1 项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认恢复'));
      await tester.pumpAndSettle();
      expect(s.questions[id]!['answer'], '先观察对称关系');
      expect(s.questions[id]!['summary'], '还要核对适用条件');
      expect(s.events.length, 3);
      expect(tester.takeException(), isNull);
      await tester.pageBack();await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('question-answer')),300,scrollable:find.byType(Scrollable).first);
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('question-answer'))).controller!.text,'先观察对称关系');
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
