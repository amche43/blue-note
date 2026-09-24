import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/editor_draft.dart';

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
  
  
}
