import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'questions.dart';
import 'learning_fields.dart';

const historyFields = {...comparisonFields, 'source': '来源与署名'};

extension HistoryRestoreStore on StudyStore {
  Future<void> restoreHistoryFields({
    required String lesson,
    required String revision,
    required Json expected,
    required Set<String> fields,
  }) async {
    if (fields.isEmpty || fields.any((k) => !historyFields.containsKey(k))) {
      throw const FormatException('请选择要恢复的内容');
    }
    if (expected['deleted'] == true) {
      throw const FormatException('条目已删除，不能从这里恢复字段');
    }
    final rows = await db.query(
      'events',
      where: 'id=? AND lesson_id=? AND type=?',
      whereArgs: [revision, lesson, 'question'],
      limit: 1,
    );
    if (rows.isEmpty) throw const FormatException('找不到此条目的历史版本');
    final historical = validateQuestion(
      jsonDecode(rows.single['payload'] as String),
    );
    if (historical['deleted'] == true) {
      throw const FormatException('不能选择删除记录作为恢复来源');
    }
    final selected = fields.where((k) => expected[k] != historical[k]).toSet();
    if (selected.isEmpty) throw const FormatException('所选内容已经与历史版本一致');
    await saveQuestion(
      {...expected, for (final k in selected) k: historical[k]},
      id: lesson,
      expected: expected,
    );
  }
}

class HistoryRestorePage extends StatefulWidget {
  final StudyStore store;
  final StudyEvent revision;
  final Json current;
  const HistoryRestorePage({
    super.key,
    required this.store,
    required this.revision,
    required this.current,
  });
  @override
  State<HistoryRestorePage> createState() => _HistoryRestorePageState();
}

class _HistoryRestorePageState extends State<HistoryRestorePage> {
  final selected = <String>{};
  bool busy = false;
  String error = '';
  Future<void> restore() async {
    if (busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复所选字段？'),
        content: Text(
          '将把 ${selected.length} 个字段恢复为这个历史版本的内容，未选中的字段保持当前值。恢复会保存为一个新版本，原有历史不会删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.store.restoreHistoryFields(
        lesson: widget.revision.lessonId,
        revision: widget.revision.id,
        expected: widget.current,
        fields: selected,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '恢复未完成，当前内容保持不变，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String value(Json q, String k) =>
      (q[k] as String? ?? '').isEmpty ? '未填写' : q[k] as String;
  @override
  Widget build(BuildContext context) {
    final old = widget.revision.payload;
    final fields = historyFields.keys
        .where((k) => (widget.current[k] ?? '') != (old[k] ?? ''))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('历史对照与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            old['title'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '历史保存时间：${DateTime.fromMillisecondsSinceEpoch(widget.revision.at).toString().substring(0, 19)}',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          const Text('默认不选择任何字段。这里比较的是已正式保存的内容，不包含尚未保存的编辑草稿。'),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (fields.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('这份历史与当前内容一致，无需恢复。'),
            ),
          for (final k in fields) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(historyFields[k]!),
              value: selected.contains(k),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(k);
                      } else {
                        selected.remove(k);
                      }
                    }),
            ),
            const Text(
              '当前已保存',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            SelectableText(value(widget.current, k)),
            const SizedBox(height: 12),
            const Text(
              '将恢复的历史内容',
              style: TextStyle(fontSize: 12, color: Color(0xff2878f0)),
            ),
            SelectableText(
              (old[k] as String? ?? '').isEmpty
                  ? '历史为空，恢复后将清空此字段'
                  : value(old, k),
            ),
            const Divider(height: 28),
          ],
          const Text(
            '题号、笔记本归属、照片识别记录及复习进度不会随字段恢复而改变。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy || selected.isEmpty ? null : restore,
            child: Text(busy ? '正在保存…' : '恢复所选 ${selected.length} 项'),
          ),
        ),
      ),
    );
  }
}
