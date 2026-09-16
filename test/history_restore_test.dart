import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/history_restore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'History restore adds a revision, preserves unselected fields, rejects stale/deleted/foreign revisions',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final id = await s.saveQuestion(
        {
          ...blankQuestion(),
          'title': '积分',
          'prompt': '求积分',
          'answer': '旧方法',
          'formula': 'x',
          'firstThought': '最初理解',
        },
        capture: {
          'ocr_raw': {'text': '原始识别'},
        },
      );
      final old = s.events.single;
      await s.saveQuestion({
        ...s.questions[id]!,
        'answer': '新方法',
        'formula': 'x^2',
        'firstThought': '现在的理解',
      }, id: id);
      await s.note(id, '独立复习笔记');
      final before = {...s.questions[id]!}, count = s.events.length;
      final capture = await s.db.query('capture_records');
      await s.restoreHistoryFields(
        lesson: id,
        revision: old.id,
        expected: before,
        fields: {'answer'},
      );
      expect(s.events.length, count + 1);
      expect(s.questions[id]!['answer'], '旧方法');
      expect(s.questions[id]!['formula'], 'x^2');
      expect(s.questions[id]!['firstThought'], '现在的理解');
      expect(s.progress(id).note, '独立复习笔记');
      expect(await s.db.query('capture_records'), capture);
      final restored = s.questions[id]!;
      await expectLater(
        s.restoreHistoryFields(
          lesson: id,
          revision: old.id,
          expected: before,
          fields: {'formula'},
        ),
        throwsFormatException,
      );
      expect(s.questions[id], restored);
      await expectLater(
        s.restoreHistoryFields(
          lesson: id,
          revision: old.id,
          expected: restored,
          fields: {'notebookId'},
        ),
        throwsFormatException,
      );
      final other = await s.saveQuestion({
        ...blankQuestion(),
        'title': '别的题',
        'prompt': '条件',
      });
      await expectLater(
        s.restoreHistoryFields(
          lesson: other,
          revision: old.id,
          expected: s.questions[other]!,
          fields: {'answer'},
        ),
        throwsFormatException,
      );
      final backup = await s.fullBackup();
      final copy = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await copy.restoreFull(backup);
      expect(copy.events.length, s.events.length);
      expect(copy.questions[id]!['answer'], '旧方法');
      await s.deleteQuestion(id);
      await expectLater(
        s.restoreHistoryFields(
          lesson: id,
          revision: old.id,
          expected: s.questions[id]!,
          fields: {'answer'},
        ),
        throwsFormatException,
      );
      await copy.db.close();
      copy.dispose();
      await s.db.close();
      s.dispose();
    },
  );
}
