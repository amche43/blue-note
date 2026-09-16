import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/editor_draft.dart';
import 'package:blue_note/entry_composer.dart';
import 'package:blue_note/question_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Draft remains when formal save fails and is atomically cleared on success',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final draft = EditorDraft(
        s,
        'editDraft:test',
        () => {
          'fields': {'title': '未完成'},
          'capture': {'source_image': 'local-only'},
        },
      )..active = true;
      draft.schedule();
      expect(await draft.flush(), isTrue);
      expect(s.questions, isEmpty);
      await s.db.execute(
        "CREATE TRIGGER fail_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'simulated save failure'); END",
      );
      await expectLater(
        s.saveQuestion({
          ...blankQuestion(),
          'title': '完成',
          'prompt': '题干',
        }, clearDraftKey: draft.key),
        throwsA(anything),
      );
      await s.refresh();
      expect(s.settings.containsKey(draft.key), isTrue);
      await s.db.execute('DROP TRIGGER fail_event');
      draft.active = false;
      await draft.settle();
      await s.saveQuestion({
        ...blankQuestion(),
        'title': '完成',
        'prompt': '题干',
      }, clearDraftKey: draft.key);
      expect(s.settings.containsKey(draft.key), isFalse);
      expect(s.questions.length, 1);
      final id=s.questions.keys.single,old={...s.questions.values.single};
      await s.saveQuestion({...old,'title':'更新后的题目'},id:id);
      draft.active=true;draft.schedule();await draft.flush();
      await expectLater(s.saveQuestion({...old,'title':'过期编辑'},id:id,expected:old,clearDraftKey:draft.key),throwsFormatException);
      await s.refresh();expect(s.questions[id]!['title'],'更新后的题目');expect(s.settings.containsKey(draft.key),isTrue);
      draft.dispose();
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Composer draft survives leaving and restores text before formal save',
    (tester) async {
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: blueNoteTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<String>(
                  ctx,
                  MaterialPageRoute(builder: (_) => EntryComposer(store: s)),
                ),
                child: const Text('录入'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('录入'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '草稿标题');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(s.settings.containsKey('editDraft:composer-question'), isTrue);
      expect(s.questions, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并退出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('录入'));
      await tester.pumpAndSettle();
      expect(find.text('继续上次的草稿？'), findsOneWidget);
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '草稿标题',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(s.settings.containsKey('editDraft:composer-question'), isFalse);
      expect(s.questions, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Restored editor refuses overwriting newer original and can save a copy',
    (tester) async {
      final s = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final q = {...blankQuestion(), 'title': '原题', 'prompt': '完整题目'};
      final id = await s.saveQuestion(q);
      await s.setting(
        'editDraft:$id',
        jsonEncode({
          'at': 0,
          'data': {
            'base': s.questions[id],
            'fields': {
              for (final e in s.questions[id]!.entries)
                if (e.key != 'deleted') e.key: e.value,
              'title': '草稿版本',
            },
            'capture': null,
          },
        }),
      );
      await s.saveQuestion({...q, 'title': '另处修改的新版本'}, id: id);
      await tester.pumpWidget(
        MaterialApp(
          theme: blueNoteTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<String>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => QuestionEditor(store: s, id: id),
                  ),
                ),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('保存题目'));
      await tester.pumpAndSettle();
      expect(s.questions[id]!['title'], '另处修改的新版本');
      await tester.scrollUntilVisible(
        find.text('另存为新条目'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('另存为新条目'));
      await tester.pumpAndSettle();
      expect(s.questions.length, 2);
      expect(s.settings.containsKey('editDraft:$id'), isFalse);
      expect(s.questions[id]!['title'], '另处修改的新版本');
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
