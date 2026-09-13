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

  void details(DateTime day, List<StudyEvent> entries) {
    final sorted = [...entries]..sort(compareEvents);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(dayKey(day), style: Theme.of(ctx).textTheme.titleLarge),
              Text('${entries.length} 次学习贡献'),
              Text(
                '整理 ${entries.where((e) => e.type == 'question').length} · 笔记 ${entries.where((e) => e.type == 'note').length} · 复习 ${entries.where((e) => e.type == 'attempt').length}',
              ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('这一天还没有保存的学习记录。'),
                ),
              ...sorted.reversed.map((e) {
                final title =
                    widget.store.lessons
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
                final at = DateTime.fromMillisecondsSinceEpoch(e.at);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    e.type == 'attempt'
                        ? Icons.check_circle_outline
                        : Icons.edit_note,
                  ),
                  title: Text(title),
                  subtitle: Text(
                    '$type · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                  ),
                  onTap: () => showDialog<void>(
                    context: ctx,
                    builder: (dialog) => AlertDialog(
                      title: Text(type),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          e.type == 'question'
                              ? '${e.payload['title']}\n${e.payload['prompt']}'
                              : e.type == 'note'
                              ? e.payload['text'] as String
                              : '${e.payload['correct'] == true ? '答对' : '需要再练'} · ${e.payload['assisted'] == true ? '使用过提示' : '独立尝试'}\n${e.payload['reason']}',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
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
          .isNotEmpty) {
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
                '学习贡献图',
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
                                        '${dayKey(date)}，${entries.length}次贡献',
                                    child: InkWell(
                                      key: ValueKey('day-${dayKey(date)}'),
                                      onTap: () => details(date, entries),
                                      child: Container(
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color:
                                              contributionColors[contributionLevel(
                                                entries.length,
                                              )],
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          border: date == today
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
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                '左右滑动 · 点击查看当天记录',
                style: TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
