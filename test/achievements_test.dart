import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/achievements.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Forks require changes and survive backup without duplicate import',
    () async {
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final book = 'book-${newId()}';
      final snapshot = <String, dynamic>{
        'source': 'book-${newId()}',
        'title': '原作',
        'items': [
          {
            'id': 'user-${newId()}',
            'question': {
              ...blankQuestion(),
              'title': '例题',
              'prompt': '求极限',
              'answer': '泰勒展开',
            },
          },
        ],
      };
      await s.createFork(book, snapshot);
      await s.createFork(book, snapshot);
      expect(s.questions.length, 1);
      expect(localAchievements(s)['fork'], 0);
      final id = s.questions.keys.single;
      await s.saveQuestion({
        ...s.questions[id]!,
        'summary': '分母是三阶，因此先比较三阶展开',
      }, id: id);
      expect(localAchievements(s)['fork'], 1);
      final backup = await s.fullBackup();
      final restored = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      await restored.restoreFull(backup);
      expect(localAchievements(restored)['fork'], 1);
      await restored.restoreFull(backup);
      expect(restored.questions.length, 1);
      await restored.db.close();
      restored.dispose();
      await s.db.close();
      s.dispose();
    },
  );
  test(
    'Thresholds follow text rules and require valid unique learning content and spaced mastery',
    () async {
      expect(achievements.first.goals, [1, 10, 50, 200]);
      expect(achievements[2].goals, [20, 100, 500, 2000]);
      for (final a in achievements) {
        for (var i = 0; i < 4; i++) {
          expect(a.level(a.goals[i]), i + 1);
          expect(a.level(a.goals[i] - 1), i);
        }
      }
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final q = {...blankQuestion(), 'title': '积分', 'prompt': '求积分'};
      await s.saveQuestion(q);
      expect(localAchievements(s)['first'], 0);
      final id = await s.saveQuestion({
        ...q,
        'answer': '对称换元',
        'errorReason': '忘记对称性',
      });
      await s.saveQuestion({...q, 'answer': '对称换元', 'errorReason': '忘记对称性'});
      expect(localAchievements(s)['first'], 1);
      expect(localAchievements(s)['hunter'], 0);
      final at = DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch;
      StudyEvent attempt(int n, int time) => StudyEvent(
        id: newId(),
        lessonId: id,
        type: 'attempt',
        at: time,
        payload: {
          'variantId': 'x',
          'rating': 'good',
          'correct': true,
          'assisted': false,
          'reason': '',
        },
      );
      await s.merge([attempt(0, at), attempt(1, at + 60000)]);
      expect(localAchievements(s)['hunter'], 0);
      await s.merge([attempt(2, at + 86400000)]);
      expect(localAchievements(s)['hunter'], 1);
      await s.attempt(
        id,
        variantId: 'x',
        rating: 'again',
        assisted: false,
        correct: false,
        reason: '还需复习',
      );
      expect(localAchievements(s)['hunter'], 0);
      expect(localAchievements(s).containsKey('accepted'), false);
      await s.db.close();
      s.dispose();
    },
  );
}
