import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/notebook_actions.dart';
import 'package:blue_note/learning_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Colors inherit consistently; study time splits midnight and stops while idle',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await s.setting('color:book-a', '2');
      expect(itemColor(s, 'book-a'), 2);
      expect(itemColor(s, 'page-a', parent: 'chapter:book-a:甲'), 2);
      await s.setting('color:chapter:book-a:甲', '4');
      expect(itemColor(s, 'page-a', parent: 'chapter:book-a:甲'), 4);
      final start = DateTime(2026, 9, 24, 23, 59, 50);
      final clock = LearningClock(s, now: start, startTimer: false);
      clock.tick(start.add(const Duration(seconds: 90)));
      await clock.writes;
      expect(learningSeconds(s, start), 10);
      expect(learningSeconds(s, DateTime(2026, 9, 25)), 50);
      clock.foreground = false;
      clock.tick(start.add(const Duration(minutes: 3)));
      await clock.writes;
      expect(learningSeconds(s, DateTime(2026, 9, 25)), 50);
      await clock.close();
      await s.db.close();
      s.dispose();
    },
  );
  testWidgets(
    'Long press enters selection; color acts on selected rows and done exits',
    (t) async {
      List<int>? picked;
      (int, int)? reordered;
      t.view.physicalSize = const Size(320, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotebookReorderList(
              onReorder: (a, b) {
                reordered = (a, b);
              },
              onColor: (ids) => picked = ids,
              children: const [
                ListTile(key: ValueKey('a'), title: Text('甲')),
                ListTile(key: ValueKey('b'), title: Text('乙')),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Checkbox), findsNothing);
      await t.longPress(find.text('甲'));
      await t.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      final drag = await t.startGesture(
        t.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await t.pump(const Duration(milliseconds: 600));
      await drag.moveBy(const Offset(0, 10));
      await t.pump(const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(0, 100));
      await t.pump(const Duration(milliseconds: 300));
      await drag.moveBy(const Offset(0, 15));
      await t.pump(const Duration(milliseconds: 200));
      await drag.up();
      await t.pumpAndSettle();
      expect(reordered, isNotNull);
      expect(t.takeException(), isNull);
      await t.tap(find.text('全选'));
      await t.pump();
      await t.tap(find.byTooltip('为选中项改色'));
      await t.pump();
      expect(picked, [0, 1]);
      await t.tap(find.text('完成'));
      await t.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
    },
  );
}
