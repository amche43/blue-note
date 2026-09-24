import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/knowledge_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Capture provenance is atomic, private and separate from confirmed content',
    () async {
      final store = await StudyStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final q = {
        ...blankQuestion(),
        'title': '端口号',
        'prompt': '自己核对过的内容',
        'contentKind': 'knowledge',
        'firstThought': '我的原话',
      };
      final capture = {
        'ocr_raw': {'text': 'OCR-PRIVATE-RAW'},
        'ai_parsed': null,
        'source_image': 'PRIVATE-IMAGE',
      };
      await expectLater(
        store.saveQuestion({...q, 'prompt': ''}, capture: capture),
        throwsFormatException,
      );
      expect(await store.db.query('capture_records'), isEmpty);
      final id = await store.saveQuestion(q, capture: capture);
      final audit = jsonDecode(
        (await store.db.query('capture_records')).single['data'] as String,
      );
      expect(audit['ocr_raw']['text'], 'OCR-PRIVATE-RAW');
      expect(audit['ai_parsed'], isNull);
      expect(audit['user_confirmed']['prompt'], '自己核对过的内容');
      expect(store.backup().contains('PRIVATE-IMAGE'), isFalse);
      final package = encodeQuestionPackage(
        id,
        store.questions[id]!,
        consent: true,
        author: '我',
      );
      expect(package.contains('OCR-PRIVATE-RAW'), isFalse);
      expect(
        decodeQuestionPackage(package)['question']['firstThought'],
        '我的原话',
      );
      await store.saveQuestion({...q, 'prompt': '再次修改'}, id: id);
      expect((await store.db.query('capture_records')).length, 1);
      expect(store.events.where((e) => e.lessonId == id).length, 2);
      await store.db.close();
      store.dispose();
    },
  );
  testWidgets('Knowledge card invites recall before showing content', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final id = await store.saveQuestion({
      ...blankQuestion(),
      'title': '熟知端口',
      'prompt': '端口知识的确认内容',
      'contentKind': 'knowledge',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgePage(store: store, id: id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('端口知识的确认内容'), findsNothing);
    await tester.tap(find.text('展开知识内容'));
    await tester.pumpAndSettle();
    expect(find.text('端口知识的确认内容'), findsOneWidget);
    expect(store.events.where((e) => e.type == 'attempt'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await store.db.close();
    store.dispose();
  });
  
}
