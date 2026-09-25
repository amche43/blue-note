import 'learning_time.dart';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';

DateTime calendarDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);
DateTime calendarStart(DateTime first) => DateTime(
  first.year,
  first.month,
  first.day - (first.weekday - DateTime.monday),
);
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Map<String, List<StudyEvent>> contributions(Iterable<StudyEvent> events) {
  final result = <String, List<StudyEvent>>{};
  for (final event in events) {
    if (['question', 'note', 'attempt'].contains(event.type)) {
      (result[dayKey(DateTime.fromMillisecondsSinceEpoch(event.at))] ??= [])
          .add(event);
    }
  }
  return result;
}

const contributionColors = [
  Color(0xffeaf1fb),
  Color(0xffbfd8fd),
  Color(0xff84b4fb),
  Color(0xff4b94f8),
  Color(0xff2878f0),
];
int contributionLevel(int n) => n == 0
    ? 0
    : n == 1
    ? 1
    : n < 4
    ? 2
    : n < 8
    ? 3
    : 4;

class ContributionCalendar extends StatefulWidget {
  final StudyStore store;
  final DateTime? today;
  const ContributionCalendar({super.key, required this.store, this.today});
  @override
  State<ContributionCalendar> createState() => _ContributionCalendarState();
}

class _ContributionCalendarState extends State<ContributionCalendar> {
  final controller = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  DateTime? selected;
  void details(DateTime day, List<StudyEvent> entries) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ContributionRecordsPage(store: widget.store, day: day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = calendarDate(widget.today ?? DateTime.now());
    final first = DateTime(today.year, today.month, today.day - 364),
        gridFirst = calendarStart(
          DateTime(today.year, today.month, today.day - 364),
        );
    final days = contributions(widget.store.events);
    var active = 0;
    for (var i = 0; i < 365; i++) {
      if ((days[dayKey(DateTime(today.year, today.month, today.day - i))] ?? [])
              .isNotEmpty ||
          learningSeconds(
                widget.store,
                DateTime(today.year, today.month, today.day - i),
              ) >
              0) {
        active++;
      }
    }
    final weeks =
        (DateTime.utc(today.year, today.month, today.day)
                    .difference(
                      DateTime.utc(
                        gridFirst.year,
                        gridFirst.month,
                        gridFirst.day,
                      ),
                    )
                    .inDays /
                7)
            .floor() +
        1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '学习图',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            Text(
              '近一年活跃 $active 天',
              style: const TextStyle(fontSize: 11, color: Color(0xff2878f0)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                const SizedBox(height: 22),
                ...['周一', '周二', '周三', '周四', '周五', '周六', '周日'].map(
                  (d) => SizedBox(
                    height: 15,
                    width: 32,
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(weeks, (week) {
                    final monday = DateTime(
                      gridFirst.year,
                      gridFirst.month,
                      gridFirst.day + week * 7,
                    );
                    final weekDates = List.generate(
                      7,
                      (day) =>
                          DateTime(monday.year, monday.month, monday.day + day),
                    );
                    return Column(
                      children: [
                        SizedBox(
                          height: 22,
                          width: 15,
                          child: OverflowBox(
                            maxWidth: 45,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              weekDates.any((d) => d.day == 1)
                                  ? '${weekDates.firstWhere((d) => d.day == 1).month}月'
                                  : week == 0
                                  ? '${first.month}月'
                                  : '',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                        ),
                        ...weekDates.map((date) {
                          final valid =
                              !date.isBefore(first) && !date.isAfter(today);
                          final entries = days[dayKey(date)] ?? [];
                          return SizedBox(
                            width: 15,
                            height: 15,
                            child: valid
                                ? Semantics(
                                    button: true,
                                    label:
                                        '${dayKey(date)}，${learningDuration(learningSeconds(widget.store, date))}，${entries.length}次贡献',
                                    child: InkWell(
                                      key: ValueKey('day-${dayKey(date)}'),
                                      onTap: () =>
                                          setState(() => selected = date),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color:
                                              contributionColors[contributionLevel(
                                                entries.length +
                                                    (learningSeconds(
                                                              widget.store,
                                                              date,
                                                            ) /
                                                            300)
                                                        .ceil(),
                                              )],
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          border: date == (selected ?? today)
                                              ? Border.all(
                                                  color: const Color(
                                                    0xff185bcc,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox(),
                          );
                        }),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
        if (selected != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${dayKey(selected!)} · ${learningDuration(learningSeconds(widget.store, selected!))} · ${days[dayKey(selected!)]?.length ?? 0} 次贡献',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff2878f0),
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    details(selected!, days[dayKey(selected!)] ?? []),
                child: const Text('查看详情'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                '左右滑动 · 点选日期',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ContributionRecordsPage extends StatelessWidget {
  final StudyStore store;
  final DateTime? day;
  final bool onlyReviews;
  const ContributionRecordsPage({
    super.key,
    required this.store,
    this.day,
    this.onlyReviews = false,
  });
  @override
  Widget build(BuildContext context) {
    final records =
        store.events
            .where(
              (e) =>
                  ['question', 'note', 'attempt'].contains(e.type) &&
                  (!onlyReviews || e.type == 'attempt') &&
                  (day == null ||
                      dayKey(DateTime.fromMillisecondsSinceEpoch(e.at)) ==
                          dayKey(day!)),
            )
            .toList()
          ..sort(compareEvents);
    return Scaffold(
      appBar: AppBar(title: Text(onlyReviews ? '复习记录' : '${dayKey(day!)} 的学习')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (day != null)
            Text('学习时长：${learningDuration(learningSeconds(store, day!))}'),
          Text(
            '共 ${records.length} 条记录',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('还没有记录。每一次整理和复习，都会留在这里。'),
            ),
          ...records.reversed.map((e) {
            final at = DateTime.fromMillisecondsSinceEpoch(e.at);
            final title =
                store.lessons
                    .where((l) => l.id == e.lessonId)
                    .firstOrNull
                    ?.title ??
                e.payload['title'] as String? ??
                '已移除的学习内容';
            final type = e.type == 'question'
                ? (e.payload['deleted'] == true ? '移除条目' : '整理条目')
                : e.type == 'note'
                ? '记录笔记'
                : '完成复习';
            final text = e.type == 'question'
                ? '${e.payload['prompt'] ?? ''}'
                : e.type == 'note'
                ? '${e.payload['text'] ?? ''}'
                : '${e.payload['correct'] == true ? '答对' : '需要再练'} · ${e.payload['assisted'] == true ? '使用过提示' : '独立尝试'}\n${e.payload['reason'] ?? ''}';
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(
                e.type == 'attempt'
                    ? Icons.check_circle_outline
                    : Icons.edit_note,
              ),
              title: Text(title),
              subtitle: Text(
                '$type · ${dayKey(at)} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(text),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
