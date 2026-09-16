import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/adoption.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Selective adoption preserves personal fields, backups and unrelated edits; undo blocks later changes',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final book = 'book-${newId()}';
      await s.createFork(book, {
        'source': 'book-${newId()}',
        'title': '原作',
        'items': [
          {
            'id': 'user-${newId()}',
            'author': '同学',
            'question': {
              ...blankQuestion(),
              'title': '例题',
              'prompt': '求极限',
              'formula': 'x',
              'answer': '旧解法',
              'firstThought': '自己的理解',
            },
          },
        ],
      });
      final id = s.questions.keys.single,
          before = {...s.questions.values.single};
      final incoming = {
        ...before,
        'formula': 'x^2',
        'answer': '新解法',
        'firstThought': '原作者的理解',
      };
      await s.adoptFields(
        lesson: id,
        expected: before,
        incoming: incoming,
        fields: {'formula', 'answer'},
      );
      expect(s.questions[id]!['firstThought'], '自己的理解');
      expect(s.questions[id]!['formula'], 'x^2');
      final record = s.adoptionHistory(book).single;
      final count = s.events.length;
      await expectLater(
        s.adoptFields(
          lesson: id,
          expected: before,
          incoming: incoming,
          fields: {'formula'},
        ),
        throwsFormatException,
      );
      expect(s.events.length, count);
      expect(s.adoptionHistory(book).length, 1);
      await s.saveQuestion({...s.questions[id]!, 'summary': '后来新增的总结'}, id: id);
      await s.undoAdoption(record['id'] as String);
      expect(s.questions[id]!['formula'], 'x');
      expect(s.questions[id]!['summary'], '后来新增的总结');
      await expectLater(
        s.undoAdoption(record['id'] as String),
        throwsFormatException,
      );
      final backup = await s.fullBackup();
      final restored = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await restored.restoreFull(backup);
      expect(restored.adoptionHistory(book).length, 1);
      expect(
        restored.settings.containsKey('adoptionUndo:${record['id']}'),
        isTrue,
      );
      await restored.restoreFull(backup);
      expect(restored.adoptionHistory(book).length, 1);
      await s.adoptFields(
        lesson: id,
        expected: {...s.questions[id]!},
        incoming: incoming,
        fields: {'answer'},
      );
      final second = s.adoptionHistory(book).first;
      await s.saveQuestion({
        ...s.questions[id]!,
        'answer': '我自己的进一步推导',
      }, id: id);
      await expectLater(
        s.undoAdoption(second['id'] as String),
        throwsFormatException,
      );
      expect(s.questions[id]!['answer'], '我自己的进一步推导');
      await s.saveQuestion({...s.questions[id]!, 'answer': '新解法'}, id: id);
      await expectLater(
        s.undoAdoption(second['id'] as String),
        throwsFormatException,
      );
      final n = s.events.length;
      await expectLater(
        s.adoptFields(
          lesson: id,
          expected: s.questions[id]!,
          incoming: incoming,
          fields: {'notebookId'},
        ),
        throwsFormatException,
      );
      expect(s.events.length, n);
      await s.db.execute("CREATE TRIGGER reject_adoption BEFORE INSERT ON settings WHEN NEW.key LIKE 'adoption:%' BEGIN SELECT RAISE(ABORT, 'simulated journal failure'); END");
      await expectLater(s.adoptFields(lesson:id,expected:s.questions[id]!,incoming:{...incoming,'formula':'x^3'},fields:{'formula'}),throwsA(anything));
      await s.db.execute('DROP TRIGGER reject_adoption');
      await s.refresh();
      expect(s.events.length,n);expect(s.questions[id]!['formula'],'x');
      await restored.db.close();
      restored.dispose();
      await s.db.close();
      s.dispose();
    },
  );
}
