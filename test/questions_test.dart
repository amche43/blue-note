import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/store.dart';

Json sample() => {
  ...blankQuestion(),
  'title': '我的积分题',
  'prompt': '求一个含 sin x 和 cos x 的积分',
  'answer': '先核对积分区间',
  'trigger': '区间与被积函数的对称性',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Question revisions survive reopen and backup; deletion cannot become a study attempt',
    () async {
      final dir = await Directory.systemTemp.createTemp('blue-note-questions-');
      final path = '${dir.path}/study.db';
      final store = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final id = await store.saveQuestion(sample());
      await store.note(id, '私人笔记');
      await store.saveQuestion({...sample(), 'title': '修改后的题目'}, id: id);
      final raw = store.backup();
      expect(jsonDecode(raw)['schemaVersion'], 2);
      expect(store.progress(id).attempts, 0);
      await store.db.close();
      store.dispose();
      final reopened = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(reopened.lessons.singleWhere((l) => l.id == id).title, '修改后的题目');
      expect(await reopened.restore(raw), 0);
      expect(reopened.progress(id).note, '私人笔记');
      await reopened.deleteQuestion(id);
      await reopened.restore(
        raw,
      ); // An older backup must not revive a later deletion.
      expect(reopened.lessons.any((l) => l.id == id), false);
      expect(reopened.progress(id).attempts, 0);
      await reopened.db.close();
      reopened.dispose();
      final resolved = dir.absolute.path;
      if (!resolved.startsWith(Directory.systemTemp.absolute.path)) {
        throw StateError('Unexpected scratch directory');
      }
      await dir.delete(recursive: true);
    },
  );

  test(
    'Sharing requires explicit consent and import never overwrites private edits',
    () async {
      final owner = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final reader = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final id = await owner.saveQuestion(sample());
      await owner.note(id, 'PRIVATE-NOTE-DO-NOT-SHARE');
      expect(
        () => encodeQuestionPackage(
          id,
          owner.questions[id]!,
          consent: false,
          author: '甲',
        ),
        throwsFormatException,
      );
      final raw = encodeQuestionPackage(
        id,
        owner.questions[id]!,
        consent: true,
        author: '甲',
      );
      expect(raw.contains('PRIVATE-NOTE-DO-NOT-SHARE'), false);
      final localId = await reader.importQuestionPackage(raw);
      expect(localId, isNot(id));
      await reader.saveQuestion({
        ...reader.questions[localId]!,
        'answer': '读者的独立解法',
      }, id: localId);
      expect(await reader.importQuestionPackage(raw), localId);
      expect(reader.questions[localId]!['answer'], '读者的独立解法');
      expect(reader.progress(localId).note, isNull);
      await owner.db.close();
      owner.dispose();
      await reader.db.close();
      reader.dispose();
    },
  );

  test(
    'Malformed packages reject before writes and knowledge suggestions remain candidates',
    () async {
      final store = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await expectLater(
        store.saveQuestion({...sample(), 'prompt': ''}),
        throwsFormatException,
      );
      expect(store.events, isEmpty);
      expect(
        suggestLessons(
          'sin x 与 cos x 的积分',
          store.bundledLessons,
        ).map((l) => l.id),
        isEmpty,
      );
      expect(suggestLessons('完全不相关的题目', store.bundledLessons), isEmpty);
      expect(decodeBackup('{"schemaVersion":1,"events":[]}'), isEmpty);
      await store.db.close();
      store.dispose();
    },
  );

  
}
