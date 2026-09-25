import 'dart:async';
import 'store.dart';

String learningDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
int learningSeconds(StudyStore store, DateTime day) =>
    int.tryParse(store.settings['studyTime:${learningDay(day)}'] ?? '0') ?? 0;
String learningDuration(int seconds) =>
    seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分钟';

class LearningClock {
  final StudyStore store;
  DateTime last, active;
  bool foreground = true;
  Timer? timer;
  final carry = <String, int>{};
  Future<void> writes = Future.value();
  LearningClock(this.store, {DateTime? now, bool startTimer = true})
    : last = now ?? DateTime.now(),
      active = now ?? DateTime.now() {
    if (startTimer) {
      timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => tick(DateTime.now()),
      );
    }
  }
  void touch() {
    tick(DateTime.now());
    active = DateTime.now();
  }

  void setForeground(bool value) {
    tick(DateTime.now());
    foreground = value;
    last = DateTime.now();
    if (value) active = last;
  }

  void tick(DateTime now) {
    var start = last;
    last = now;
    if (!foreground || !now.isAfter(start)) return;
    final limit = active.add(const Duration(seconds: 60));
    final end = now.isBefore(limit) ? now : limit;
    while (start.isBefore(end)) {
      final midnight = DateTime(start.year, start.month, start.day + 1);
      final stop = end.isBefore(midnight) ? end : midnight;
      final key = learningDay(start);
      final ms = stop.difference(start).inMilliseconds + (carry[key] ?? 0);
      final seconds = ms ~/ 1000;
      carry[key] = ms % 1000;
      final day = start;
      if (seconds > 0) {
        writes = writes
            .then((_) async {
              final total = (learningSeconds(store, day) + seconds).clamp(
                0,
                86400,
              );
              await store.setting(
                'studyTime:${learningDay(day)}',
                total.toString(),
              );
            })
            .catchError((Object _) {
              /* Keep drawing available if the optional statistic cannot be saved. */
            });
      }
      start = stop;
    }
  }

  Future<void> close() {
    timer?.cancel();
    tick(DateTime.now());
    foreground = false;
    return writes;
  }
}
