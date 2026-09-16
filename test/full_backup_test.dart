import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/full_backup.dart';
import 'package:blue_note/backup_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  Future<StudyStore> open() => StudyStore.open(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
  test(
    'Full backup restores photos, empty books, progress, favorites; excludes credentials and rolls back conflicts',
    () async {
      final a = await open(), b = await open();
      final photo = base64Encode(
        (await rootBundle.load(
          'assets/brand/app-icon.png',
        )).buffer.asUint8List(),
      );
      final id = await a.saveQuestion(
        {...blankQuestion(), 'title': '我的题目', 'prompt': '题干'},
        capture: {
          'source_image': photo,
          'ocr_raw': {'text': '原始题干'},
          'ai_parsed': null,
        },
      );
      await a.note(id, '私人思考');
      await a.attempt(
        id,
        variantId: 'self',
        rating: 'good',
        assisted: false,
        correct: true,
        reason: '理解了',
      );
      await a.setting(
        'notebook:empty',
        jsonEncode({'title': '空知识本', 'kind': 'knowledge'}),
      );
      await a.setting('favorite:$id', 'true');
      await a.setting('community', 'SECRET_TOKEN');
      await a.setting('avatarImage', 'SERVER_APPROVED_ONLY');
      final raw = await a.fullBackup();
      expect(raw.contains('SECRET_TOKEN'), false);
      expect(raw.contains('SERVER_APPROVED_ONLY'), false);
      expect(await b.restoreFull(raw), 3);
      expect(b.progress(id).note, '私人思考');
      expect(b.progress(id).attempts, 1);
      expect(b.settings['favorite:$id'], 'true');
      expect(b.settings['notebook:empty'], a.settings['notebook:empty']);
      expect(
        (await b.db.query('capture_records')).single['data'],
        (await a.db.query('capture_records')).single['data'],
      );
      expect(await b.restoreFull(raw), 0);
      await b.setting(
        'notebook:empty',
        jsonEncode({'title': '本机更新', 'kind': 'knowledge'}),
      );
      await b.restoreFull(raw);
      expect(b.settings['notebook:empty'], contains('本机更新'));
      final corrupt = jsonDecode(raw) as Map<String, dynamic>;
      (corrupt['events'] as List).last['payload']['reason'] = '冲突';
      (corrupt['settings'] as Map)['notebook:new'] = jsonEncode({
        'title': '不应落盘',
        'kind': 'question',
      });
      await expectLater(
        b.restoreFull(jsonEncode(corrupt)),
        throwsFormatException,
      );
      await b.refresh();
      expect(b.settings.containsKey('notebook:new'), false);
      expect(b.events.length, 3);
      corrupt['settings'] = {'community': 'BAD'};
      expect(
        () => FullBackup.decode(jsonEncode(corrupt)),
        throwsFormatException,
      );
      await a.db.close();
      await b.db.close();
      a.dispose();
      b.dispose();
    },
  );
  testWidgets(
    'File backup cancellation and confirmed restore use the native channel',
    (tester) async {
      final store = (await tester.runAsync(open))!;
      await tester.runAsync(() => store.note('math-symmetry', '已保存'));
      Uint8List? file;
      const channel = MethodChannel('blue_note/backup');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'save') {
          file = (call.arguments as Map)['bytes'] as Uint8List;
          return true;
        }
        return file;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BackupPage(
            store: store,
            legacyExport: () {},
            legacyImport: () {},
          ),
        ),
      );
      await tester.runAsync(() async { await tester.tap(find.text('保存完整备份文件')); await Future<void>.delayed(const Duration(milliseconds:200)); });
      await tester.pumpAndSettle();
      expect(find.text('完整备份已保存到所选位置'), findsOneWidget);
      expect(file, isNotNull);
      await tester.tap(find.text('选择备份文件恢复'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds:400));
      expect(find.text('确认恢复内容'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.events.length, 1);
      await tester.tap(find.text('选择备份文件恢复'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds:400));
      await tester.runAsync(() async { await tester.tap(find.text('合并恢复')); await Future<void>.delayed(const Duration(milliseconds:200)); });
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复完成，新增 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.db.close());
      store.dispose();
    },
  );
}
