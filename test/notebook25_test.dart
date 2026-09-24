import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/notebook_actions.dart';
import 'package:blue_note/notebook_ui.dart';
import 'package:blue_note/chapter_page.dart';
import 'package:blue_note/ink_page.dart';
import 'package:blue_note/ink_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Expanded canvas dimensions survive edits and reject invalid widths',
    () {
      const doc = InkDocument(width: 2500, height: 4500);
      expect(
        InkDocument.decode(
          doc.withElements([]).insertSpace(20, 100).encode(),
        ).width,
        2500,
      );
      final legacy = jsonDecode(doc.encode()) as Map<String, dynamic>;
      legacy.remove('width');
      expect(InkDocument.decode(jsonEncode(legacy)).width, 1000);
      legacy['width'] = -1;
      expect(
        () => InkDocument.decode(jsonEncode(legacy)),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'Reorder persists; cancel chapter deletion preserves pages; confirm is atomic',
    (t) async {
      final s = (await t.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      final book = 'book-${'a' * 32}';
      await s.setting(
        'notebook:$book',
        jsonEncode({
          'title': '数学',
          'kind': 'question',
          'chapters': ['甲', '乙'],
        }),
      );
      final a = await s.saveQuestion({
        ...blankQuestion(),
        'title': '甲页',
        'canvas': const InkDocument().encode(),
        'notebookId': book,
        'notebookTitle': '数学',
        'chapter': '甲',
      });
      final b = await s.saveQuestion({
        ...blankQuestion(),
        'title': '乙页',
        'canvas': const InkDocument().encode(),
        'notebookId': book,
        'notebookTitle': '数学',
        'chapter': '乙',
      });
      await reorderItems(s, 'chapters:$book', ['甲', '乙'], 0, 2);
      expect(notebookChapters(s, book), ['乙', '甲']);
      expect(entryIconState(s, a), NoteIconState.local);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => deleteChapter(ctx, s, book, '甲'),
              child: const Text('删章'),
            ),
          ),
        ),
      );
      await t.tap(find.text('删章'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(s.questions[a]!['deleted'], false);
      await t.tap(find.text('删章'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认删除'));
      await t.pumpAndSettle();
      expect(s.questions[a]!['deleted'], true);
      expect(s.questions[b]!['deleted'], false);
      expect(notebookChapters(s, book), ['乙']);
      await t.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Back silently saves edits, leaves no draft prompt and blank rename retains a title',
    (t) async {
      final s = (await t.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Navigator.push<void>(
                ctx,
                MaterialPageRoute(builder: (_) => InkPage(store: s)),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开'));
      await t.pumpAndSettle();
      final area = t.getRect(find.byKey(const ValueKey('ink-canvas')));
      await t.dragFrom(
        Offset(area.right - 12, area.top + 100),
        const Offset(-70, 30),
      );
      await t.pump(const Duration(milliseconds: 1100));
      await t.pumpAndSettle();
      expect(
        InkDocument.decode(s.questions.values.single['canvas'] as String).width,
        greaterThan(1000),
      );
      await t.enterText(find.byType(TextField).first, '我的推导');
      await t.tap(find.byTooltip('返回'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(s.questions.values.single['title'], '我的推导');
      expect(s.settings.keys.where((k) => k.startsWith('editDraft:')), isEmpty);
      await t.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
