import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/contribution_calendar.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Calendar aligns with Monday across months and counts only real events',
    () {
      expect(calendarStart(DateTime(2026, 1, 1)), DateTime(2025, 12, 29));
      expect(calendarStart(DateTime(2024, 3, 1)).weekday, DateTime.monday);
      expect([0, 1, 2, 3, 4, 7, 8, 100].map(contributionLevel), [
        0,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
      ]);
      final event = StudyEvent(
        id: 'a' * 32,
        lessonId: 'math-symmetry',
        type: 'note',
        at: DateTime(2026, 9, 11, 23, 50).millisecondsSinceEpoch,
        payload: {'text': '自己的推导'},
      );
      expect(contributions([event])['2026-09-11']!.length, 1);
    },
  );
  testWidgets(
    'Tapping a day opens its actual contributions and record details',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = (await tester.runAsync(
        () => StudyStore.open(
          factory: databaseFactoryFfiNoIsolate,
          path: inMemoryDatabasePath,
        ),
      ))!;
      store.events = [
        StudyEvent(
          id: 'a' * 32,
          lessonId: 'math-symmetry',
          type: 'note',
          at: DateTime(2026, 9, 11, 12).millisecondsSinceEpoch,
          payload: {'text': '自己的推导'},
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContributionCalendar(
              store: store,
              today: DateTime(2026, 9, 11),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周日'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-2026-09-11')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('2026-09-11 · 1 次贡献'), findsOneWidget);
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('先互换，再相加'));
      await tester.pumpAndSettle();
      expect(find.text('自己的推导'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      store.dispose();
    },
  );
}
