import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/notebooks.dart';
import 'package:blue_note/ink_page.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Photo entries round trip with optional title and old records remain editable',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final id = await s.saveQuestion({
        ...blankQuestion(),
        'questionPhoto': pixel,
        'answerPhoto': pixel,
      });
      expect(s.questions[id]!['title'], '未命名题目');
      final raw = encodeQuestionPackage(
        id,
        s.questions[id]!,
        consent: true,
        author: '同学',
      );
      expect(decodeQuestionPackage(raw)['question']['answerPhoto'], pixel);
      expect(questionLesson(id, s.questions[id]!).steps, isNotEmpty);
      final old = {...blankQuestion(), 'title': '旧题', 'prompt': '题干'}
        ..remove('questionPhoto')
        ..remove('answerPhoto');
      final oldId = await s.saveQuestion(old);
      final expected = s.questions[oldId]!;
      await s.saveQuestion(
        {...expected, 'title': '新版标题'},
        id: oldId,
        expected: expected,
      );
      expect(s.questions[oldId]!['title'], '新版标题');
      expect(
        () => validateQuestion({...blankQuestion(), 'title': '空题'}),
        throwsFormatException,
      );
      final backup = await s.fullBackup();
      await s.db.close();
      s.dispose();
      final restored = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await restored.restoreFull(backup);
      expect(restored.questions[id]!['questionPhoto'], pixel);
      await restored.db.close();
      restored.dispose();
    },
  );
  
  testWidgets('Notebook chapters reveal titles before opening full content', (
    tester,
  ) async {
    final s = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final book = 'book-${'a' * 32}';
    await s.saveQuestion({
      ...blankQuestion(),
      'title': '理发师问题',
      'prompt': '完整题目',
      'chapter': '进程同步',
      'notebookId': book,
      'notebookTitle': 'OS',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NotebooksPage(
          store: s,
          initialBook: book,
          openLesson: (l) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('完整题目'), findsNothing);
    await tester.tap(find.text('进程同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('理发师问题'));
    await tester.pumpAndSettle();
    expect(find.byType(InkPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await s.db.close();
    s.dispose();
  });
}
