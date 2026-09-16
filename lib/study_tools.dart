import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'domain.dart';
import 'store.dart';

StudyEvent? latestAttempt(StudyStore store, String id) {
  final events =
      store.events
          .where((e) => e.type == 'attempt' && e.lessonId == id)
          .toList()
        ..sort(compareEvents);
  return events.lastOrNull;
}

bool needsPractice(StudyEvent? event) =>
    event != null &&
    (event.payload['correct'] != true ||
        event.payload['assisted'] == true ||
        event.payload['rating'] != 'good');

class StudyCenter extends StatefulWidget {
  final StudyStore store;
  final Future<void> Function(Lesson lesson, bool review) openLesson;
  const StudyCenter({super.key, required this.store, required this.openLesson});
  @override
  State<StudyCenter> createState() => _StudyCenterState();
}

class _StudyCenterState extends State<StudyCenter> {
  String filter = '到期复习', subject = '全部科目', reason = '全部卡点';
  bool session = false;
  StudyStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    store.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(changed);
    super.dispose();
  }

  List<Lesson> get filtered {
    final dueIds = store.due.map((e) => e.id).toSet();
    return store.lessons.where((l) {
      final last = latestAttempt(store, l.id);
      if (subject != '全部科目' && l.subject != subject) return false;
      if (reason != '全部卡点' && last?.payload['reason'] != reason) return false;
      return switch (filter) {
        '到期复习' => dueIds.contains(l.id),
        '待再练' => needsPractice(last),
        '收藏' => store.settings['favorite:${l.id}'] == 'true',
        _ => last != null,
      };
    }).toList();
  }

  Future<void> startSession() async {
    final queue = filtered.where((l) => l.variants.isNotEmpty).toList()
      ..shuffle();
    if (queue.isEmpty) return;
    setState(() => session = true);
    int completed = 0;
    try {
      for (final lesson in queue.take(5)) {
        if (!mounted) break;
        final before = store.events
            .where((e) => e.type == 'attempt')
            .map((e) => e.id)
            .toSet();
        await widget.openLesson(lesson, true);
        if (!mounted) break;
        final added = store.events.any(
          (e) =>
              e.type == 'attempt' &&
              !before.contains(e.id) &&
              e.lessonId == lesson.id,
        );
        if (!added) break; // Backing out without answering ends this session.
        completed++;
        if (completed >= queue.length.clamp(0, 5)) break;
        final next = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('本轮已完成 $completed 个单元'),
            content: const Text('下一题会换一个单元，先独立判断该用什么思路。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('结束本轮'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续下一题'),
              ),
            ],
          ),
        );
        if (next != true) break;
      }
    } finally {
      if (mounted) {
        setState(() => session = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本轮完成 $completed 个单元，已作答记录均已保存')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final attempts = store.events.where((e) => e.type == 'attempt').toList();
    final today = attempts
        .where((e) {
          final t = DateTime.fromMillisecondsSinceEpoch(e.at);
          return t.year == now.year && t.month == now.month && t.day == now.day;
        })
        .map((e) => e.lessonId)
        .toSet()
        .length;
    final independent = attempts
        .where(
          (e) =>
              e.payload['correct'] == true &&
              e.payload['assisted'] == false &&
              e.payload['rating'] == 'good',
        )
        .length;
    final list = filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('复习与回想')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '今天练过 $today 个单元',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('累计 ${attempts.length} 次作答 · $independent 次独立答对'),
          const Text(
            '统计反映作答记录，不代表已经掌握。今日同一单元只计一次。',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: ['到期复习', '待再练', '收藏', '已练习']
                .map(
                  (v) => ChoiceChip(
                    label: Text(v),
                    selected: filter == v,
                    onSelected: session
                        ? null
                        : (_) => setState(() => filter = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: subject,
            decoration: const InputDecoration(labelText: '科目'),
            items: [
              '全部科目',
              ...store.lessons.map((l) => l.subject).toSet(),
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: session ? null : (v) => setState(() => subject = v!),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: reason,
            decoration: const InputDecoration(labelText: '最近一次作答的卡点'),
            items: [
              '全部卡点',
              '没想到用',
              '忘记了',
              '条件理解错',
              '计算出错',
              '没有卡住',
              '暂未判断',
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: session ? null : (v) => setState(() => reason = v!),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: session || !list.any((l) => l.variants.isNotEmpty)
                ? null
                : startSession,
            icon: const Icon(Icons.shuffle),
            label: const Text('混合练一轮 · 最多5个单元'),
          ),
          const Text(
            '混练使用已有变式，每个单元进入时隐藏方法名称。无变式的自建题可通过右侧按钮回想。',
            style: TextStyle(fontSize: 13),
          ),
          if (filter == '收藏')
            const Text(
              '收藏保存在本机，可随完整备份迁移，不随旧版文字备份或同步。',
              style: TextStyle(fontSize: 13),
            ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('这里暂时没有题目，可以切换筛选条件。'),
            ),
          ...list.map(
            (l) => Card(
              child: ListTile(
                title: Text(l.title),
                subtitle: Text(
                  '${l.subject} · ${store.progress(l.id).status}\n最近卡点：${latestAttempt(store, l.id)?.payload['reason'] ?? '尚未记录'}',
                ),
                isThreeLine: true,
                onTap: session
                    ? null
                    : () => widget.openLesson(l, l.variants.isNotEmpty),
                trailing: IconButton(
                  tooltip: '关键点回想',
                  icon: const Icon(Icons.psychology_outlined),
                  onPressed: session
                      ? null
                      : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecallPage(store: store, lesson: l),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RecallPage extends StatefulWidget {
  final StudyStore store;
  final Lesson lesson;
  const RecallPage({super.key, required this.store, required this.lesson});
  @override
  State<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<RecallPage> {
  final trigger = TextEditingController(),
      action = TextEditingController(),
      boundary = TextEditingController();
  bool revealed = false, busy = false, saved = false, discard = false;
  bool get dirty =>
      !saved &&
      [trigger, action, boundary].any((c) => c.text.trim().isNotEmpty);
  @override
  void dispose() {
    trigger.dispose();
    action.dispose();
    boundary.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final text =
        '【主动回想】\n看到什么：${trigger.text.trim()}\n先做什么：${action.text.trim()}\n适用条件或误用边界：${boundary.text.trim()}';
    if ([trigger, action, boundary].every((c) => c.text.trim().isEmpty)) return;
    setState(() => busy = true);
    try {
      // Existing note remains intact; the learner explicitly appends this reflection.
      final old = widget.store.progress(widget.lesson.id).note ?? '';
      final combined = old.isEmpty ? text : '$old\n\n$text';
      if (combined.length > 20000) {
        throw const FormatException('笔记已接近容量上限，请先整理已有笔记');
      }
      await widget.store.note(widget.lesson.id, combined);
      if (mounted) setState(() => saved = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FormatException ? e.message : '未保存，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && (!dirty || discard),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || busy) return;
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('这次回想还没保存'),
          content: const Text('返回继续编辑，或放弃本次输入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('放弃并离开'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => discard = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('先回想，再核对')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.lesson.subject,
            style: const TextStyle(color: Colors.black54),
          ),
          Text(widget.lesson.prompt),
          if (widget.lesson.formula != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                widget.lesson.formula!,
                onErrorFallback: (_) => Text(widget.lesson.formula!),
              ),
            ),
          const SizedBox(height: 18),
          const Text('先写下自己的判断。需要时可以直接展开参考；这里不自动评分，也不会把自评计为独立答对。'),
          ...[
            (trigger, '题目中哪个条件提醒了你？'),
            (action, '第一步准备做什么？'),
            (boundary, '这个方法什么时候不能用？'),
          ].map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: item.$1,
                enabled: !saved && !busy,
                maxLines: 3,
                maxLength: 1500,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: item.$2,
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => revealed = !revealed),
            child: Text(revealed ? '收起参考，再回想一次' : '展开关键点参考'),
          ),
          if (revealed)
            ...widget.lesson.blue.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${{'trigger': '触发条件', 'action': '关键动作', 'conditions': '适用条件', 'pitfall': '容易误用'}[e.key] ?? e.key}\n${e.value}',
                ),
              ),
            ),
          FilledButton(
            onPressed: saved || busy ? null : save,
            child: Text(saved ? '已追加到蓝笔笔记' : '把这次回想追加到笔记'),
          ),
          const Text(
            '离开前请保存需要保留的内容。原有笔记不会被覆盖。',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
