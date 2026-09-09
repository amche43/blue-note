import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/store.dart';

class ReceiptClient extends CommunityClient {
  bool fail = true;
  final List<Json> sent = [];
  ReceiptClient() : super({'url': 'https://10.0.2.2:8788'});
  @override Future<Json> request(String method, String path, [Json? data]) async {
    if (data != null) sent.add(data);
    if (fail) throw const SocketException('response lost');
    return {'id': 'server-id', 'status': 'pending', 'reply': ''};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Lost acknowledgment remains unsent, survives reopen and retries with same identity', () async {
    final dir = await Directory.systemTemp.createTemp('blue-note-feedback-');
    final path = '${dir.path}/study.db';
    var store = await StudyStore.open(factory: databaseFactoryFfi, path: path);
    var repository = FeedbackRepository(store);
    await repository.draft('math-symmetry', '对称积分', '请补充条件');
    final id = repository.items.single['requestId'];
    final client = ReceiptClient();
    await expectLater(repository.submit(repository.items.single, client, 'tester-a'), throwsA(isA<SocketException>()));
    expect(repository.items.single['status'], 'draft');
    await store.db.close(); store.dispose();
    store = await StudyStore.open(factory: databaseFactoryFfi, path: path);
    repository = FeedbackRepository(store);
    expect(repository.items.single['requestId'], id);
    expect(repository.items.single['status'], 'draft');
    await expectLater(repository.submit(repository.items.single, client, 'tester-b'), throwsFormatException);
    expect(client.sent.length, 1);
    client.fail = false;
    await repository.submit(repository.items.single, client, 'tester-a');
    expect(client.sent[0], client.sent[1]);
    expect(repository.items.single['status'], 'pending');
    expect(store.backup(), isNot(contains('请补充条件')));
    await store.db.close(); store.dispose();
    await dir.delete(recursive: true);
  });
  test('Local community never accepts cleartext or remote custom certificates', () {
    for (final url in ['http://10.0.2.2:8788', 'https://example.com', 'https://localhost@evil.example', 'https://localhost/path']) {
      expect(() => CommunityClient.parse('{"url":"$url"}'), throwsFormatException);
    }
  });
  testWidgets('Feedback form saves locally and never offers submission while disconnected', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(() => StudyStore.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath)))!;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => createFeedback(context, store, 'math-symmetry', '对称积分'), child: const Text('反馈'))))));
    await tester.tap(find.text('反馈')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '请补充适用条件');
    await tester.tap(find.text('保存反馈')); await tester.pumpAndSettle();
    expect(find.text('尚未提交'), findsOneWidget);
    expect(find.text('请补充适用条件'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '提交 / 重试')).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
    await store.db.close(); store.dispose();
  });
}
