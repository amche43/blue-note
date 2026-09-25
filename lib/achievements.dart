import 'ink_document.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';

class Achievement {
  final String id, name, english, rule, unit;
  final List<int> goals;
  final IconData icon;
  const Achievement(
    this.id,
    this.name,
    this.english,
    this.goals,
    this.unit,
    this.icon,
    this.rule,
  );
  int level(int value) => goals.where((n) => value >= n).length;
}

const achievements = [
  Achievement(
    'first',
    '初次记录',
    'First Note',
    [1, 10, 50, 200],
    '条',
    Icons.edit_note,
    '题目正文加一项突破点、理解、错误原因、解题思路或总结；相同内容去重。',
  ),
  Achievement(
    'open',
    '开源学习者',
    'Open Learner',
    [1, 3, 10, 25],
    '本',
    Icons.public,
    '每本至少 3 条有效且不同的内容，公开满 7 天；空本子不计。',
  ),
  Achievement(
    'knowledge',
    '知识构建者',
    'Knowledge Builder',
    [20, 100, 500, 2000],
    '个',
    Icons.auto_stories,
    '有正文和解释的知识条目，重复内容不计。',
  ),
  Achievement(
    'hunter',
    '错题猎手',
    'Mistake Hunter',
    [10, 50, 200, 1000],
    '道',
    Icons.search,
    '曾记录错误原因或做错，之后至少两次独立答对，间隔至少 24 小时，且目前仍掌握。',
  ),
  Achievement(
    'contribution',
    '初次贡献',
    'First Contribution',
    [1, 10, 50, 200],
    '次',
    Icons.add_comment_outlined,
    '向他人条目提交不同的有效改进；被拒绝的提案不计，自我贡献不计。',
  ),
  Achievement(
    'maintainer',
    '持续维护者',
    'Maintainer',
    [4, 12, 26, 52],
    '周',
    Icons.update,
    '同一本在最近 56 周中的有效维护周数，允许少量休息；每天登录不计。',
  ),
  Achievement(
    'collaborator',
    '协作伙伴',
    'Collaborator',
    [1, 3, 8, 20],
    '个',
    Icons.groups_outlined,
    '加入他人本子且实际维护简介或贡献被采纳；仅加入不计。',
  ),
  Achievement(
    'accepted',
    '改进已采纳',
    'Merge Accepted',
    [1, 10, 50, 200],
    '次',
    Icons.merge,
    '他人作者接受的不同改进，以后台处理结果为准。',
  ),
  Achievement(
    'fork',
    '版本延展者',
    'Fork Explorer',
    [1, 5, 20, 50],
    '本',
    Icons.fork_right,
    '派生后新增有效内容或修改正文与理解才计入，同一来源只计一本。公开履历仅统计已公开的修改。',
  ),
  Achievement(
    'popular',
    '人气笔记本',
    'Popular Notebook',
    [10, 100, 500, 2000],
    'Star',
    Icons.star_outline,
    '单个公开笔记本的独立用户收藏数，排除作者自己，不累加多个本子。',
  ),
  Achievement(
    'helpful',
    '学习引路人',
    'Helpful Mentor',
    [10, 50, 200, 1000],
    '人',
    Icons.lightbulb_outline,
    '其他用户标记“帮我理解了”；同一个人对你多条内容的标记只计一人。',
  ),
  Achievement(
    'momentum',
    '持续进步',
    'Learning Momentum',
    [4, 12, 26, 52],
    '周',
    Icons.trending_up,
    '过去 52 周中，有有效学习成果或累计学习满 30 分钟的周，不要求连续签到。',
  ),
];
const tierNames = ['尚未达成', '初级', '进阶', '优秀', '卓越'];
bool annotatedCanvas(Json q) {
  try {
    final doc = InkDocument.decode(q['canvas'] as String? ?? '');
    return doc.elements.any((e) => e.note.trim().isNotEmpty);
  } catch (_) {
    return false;
  }
}

bool validLearning(Json q) =>
    q['deleted'] != true &&
    (annotatedCanvas(q) ||
        ((q['prompt'] as String? ?? '').trim().isNotEmpty &&
            [
              'trigger',
              'action',
              'answer',
              'firstThought',
              'errorReason',
              'summary',
              'conditions',
              'pitfall',
            ].any((k) => (q[k] as String? ?? '').trim().isNotEmpty)));
String learningFingerprint(Json q) => jsonEncode([
  if ((q['canvas'] as String? ?? '').isNotEmpty) q['canvas'],
  for (final k in [
    'prompt',
    'trigger',
    'action',
    'answer',
    'firstThought',
    'errorReason',
    'summary',
    'conditions',
    'pitfall',
  ])
    (q[k] as String? ?? '').replaceAll(RegExp(r'\s+'), ''),
]);
String learningWeek(DateTime d) {
  final date = DateTime.utc(d.year, d.month, d.day);
  return date
      .subtract(Duration(days: date.weekday - 1))
      .toIso8601String()
      .substring(0, 10);
}

Map<String, int> localAchievements(StudyStore store, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final seen = <String>{};
  int knowledge = 0, hunter = 0;
  final ids = <String>{};
  for (final e in store.questions.entries) {
    final q = {...e.value};
    final note = store.progress(e.key).note;
    if ((q['firstThought'] ?? '') == '' && note != null) {
      q['firstThought'] = note;
    }
    if (!validLearning(q)) continue;
    ids.add(e.key);
    if (!seen.add(learningFingerprint(q))) continue;
    if (q['contentKind'] == 'knowledge') knowledge++;
    final wrong =
        (q['errorReason'] as String? ?? '').trim().isNotEmpty ||
        store.events.any(
          (event) =>
              event.lessonId == e.key &&
              event.type == 'attempt' &&
              event.payload['correct'] == false,
        );
    if (q['contentKind'] != 'knowledge' &&
        wrong &&
        store.progress(e.key).independent >= 2) {
      hunter++;
    }
  }
  final weeks = <String>{},
      byBook = <String, Set<String>>{},
      seenWork = <String>{};
  final ordered = [...store.events]..sort(compareEvents);
  final latestReview = <String, int>{};
  for (final e in ordered) {
    final d = DateTime.fromMillisecondsSinceEpoch(e.at);
    if (d.isAfter(today)) continue;
    bool valid = false;
    if (e.type == 'question' && validLearning(e.payload)) {
      valid = seenWork.add('${e.lessonId}:${learningFingerprint(e.payload)}');
    }
    if (e.type == 'note' &&
        ids.contains(e.lessonId) &&
        (e.payload['text'] as String).trim().isNotEmpty) {
      valid = seenWork.add('${e.lessonId}:note:${e.payload['text']}');
    }
    if (e.type == 'attempt' &&
        e.payload['correct'] == true &&
        e.payload['assisted'] == false &&
        e.payload['rating'] == 'good') {
      final last = latestReview[e.lessonId];
      valid = last == null || e.at - last >= 86400000;
      if (valid) latestReview[e.lessonId] = e.at;
    }
    if (!valid) continue;
    final w = learningWeek(d);
    if (!d.isBefore(today.subtract(const Duration(days: 364)))) weeks.add(w);
    final b = (store.questions[e.lessonId]?['notebookId'] as String? ?? '');
    if (b.isNotEmpty &&
        !d.isBefore(today.subtract(const Duration(days: 392)))) {
      (byBook[b] ??= <String>{}).add(w);
    }
  }
  final studyWeeks = <String, int>{};
  for (final e in store.settings.entries.where(
    (e) => e.key.startsWith('studyTime:'),
  )) {
    final d = DateTime.tryParse(e.key.substring(10));
    if (d == null ||
        d.isAfter(today) ||
        d.isBefore(today.subtract(const Duration(days: 364)))) {
      continue;
    }
    final w = learningWeek(d);
    studyWeeks[w] = (studyWeeks[w] ?? 0) + (int.tryParse(e.value) ?? 0);
  }
  weeks.addAll(
    studyWeeks.entries.where((e) => e.value >= 1800).map((e) => e.key),
  );
  final changedSources = <String>{};
  for (final item in store.settings.entries.where(
    (e) => e.key.startsWith('fork:'),
  )) {
    final snapshot = jsonDecode(item.value) as Json;
    final baseline = (snapshot['items'] as List)
        .map((p) => learningFingerprint(p['question'] as Json))
        .toSet();
    final book = item.key.substring(5);
    if (store.questions.values.any(
      (q) =>
          q['notebookId'] == book &&
          validLearning(q) &&
          !baseline.contains(learningFingerprint(q)),
    )) {
      changedSources.add(snapshot['source'] as String);
    }
  }
  return {
    'fork': changedSources.length,
    'first': seen.length,
    'knowledge': knowledge,
    'hunter': hunter,
    'maintainer': math.min(
      52,
      byBook.values.fold<int>(0, (n, v) => math.max(n, v.length)),
    ),
    'momentum': math.min(52, weeks.length),
  };
}

class AchievementBadge extends StatelessWidget {
  final IconData icon;
  final int level;
  final double size;
  const AchievementBadge({
    super.key,
    required this.icon,
    required this.level,
    this.size = 64,
  });
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xffb8c6d9),
      const Color(0xffb98057),
      const Color(0xff9ba9bf),
      const Color(0xffedb735),
      const Color(0xff2878f0),
    ];
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BadgePaint(colors[level]),
        child: Center(
          child: Icon(icon, size: size * .42, color: Colors.white),
        ),
      ),
    );
  }
}

class _BadgePaint extends CustomPainter {
  final Color color;
  _BadgePaint(this.color);
  @override
  void paint(Canvas c, Size s) {
    Path hex(double radius) {
      final p = Path();
      for (var n = 0; n < 6; n++) {
        final a = (n * 60 - 90) * math.pi / 180;
        final x = s.width / 2 + radius * math.cos(a),
            y = s.height / 2 + radius * math.sin(a);
        if (n == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      return p..close();
    }

    final outer = hex(s.width * .47);
    c.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .72)!,
            color,
            Color.lerp(color, Colors.black, .18)!,
          ],
        ).createShader(Offset.zero & s),
    );
    c.drawPath(hex(s.width * .37), Paint()..color = color);
    c.drawPath(
      hex(s.width * .37),
      Paint()
        ..color = Colors.white.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * .025,
    );
  }

  @override
  bool shouldRepaint(_BadgePaint old) => old.color != color;
}
