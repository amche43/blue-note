import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'adoption.dart';
import 'learning_fields.dart';

class AdoptionPage extends StatefulWidget {
  final StudyStore store;
  final String lesson;
  final Json before, incoming;
  const AdoptionPage({
    super.key,
    required this.store,
    required this.lesson,
    required this.before,
    required this.incoming,
  });
  @override
  State<AdoptionPage> createState() => _AdoptionPageState();
}

class _AdoptionPageState extends State<AdoptionPage> {
  final selected = <String>{};
  bool busy = false;
  String error = '';
  Future<void> save() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认采纳所选内容？'),
        content: Text(
          '将替换 ${selected.length} 个字段。未选中的内容保持不变，本次采纳会保留前后版本供查看与撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认采纳'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.store.adoptFields(
        lesson: widget.lesson,
        expected: widget.before,
        incoming: widget.incoming,
        fields: selected,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '未能保存，原内容保持不变，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = comparisonFields.keys
        .where((k) => (widget.before[k] ?? '') != (widget.incoming[k] ?? ''))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('选择要采纳的内容')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.before['title'] as String,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('默认不选择任何字段。逐项核对，自己的理解由自己决定。原作可能继续更新，本次采纳的是刚才对照页读取的版本。'),
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
              padding: EdgeInsets.all(24),
              child: Text('当前内容已经与原作一致。'),
            ),
          for (final k in fields) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected.contains(k),
              title: Text(comparisonFields[k]!),
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
              '我的当前内容',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            SelectableText(
              (widget.before[k] as String? ?? '').isEmpty
                  ? '未填写'
                  : widget.before[k] as String,
            ),
            const SizedBox(height: 10),
            const Text(
              '将采用的原作内容',
              style: TextStyle(fontSize: 12, color: Color(0xff2878f0)),
            ),
            SelectableText(
              (widget.incoming[k] as String? ?? '').isEmpty
                  ? '原作为空，采纳后会清空此字段'
                  : widget.incoming[k] as String,
            ),
            const Divider(height: 28),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy || selected.isEmpty ? null : save,
            child: Text(busy ? '正在保存…' : '采纳所选 ${selected.length} 项'),
          ),
        ),
      ),
    );
  }
}

class AdoptionHistoryPage extends StatefulWidget {
  final StudyStore store;
  final String book;
  const AdoptionHistoryPage({
    super.key,
    required this.store,
    required this.book,
  });
  @override
  State<AdoptionHistoryPage> createState() => _AdoptionHistoryPageState();
}

class _AdoptionHistoryPageState extends State<AdoptionHistoryPage> {
  bool busy = false;
  String error = '';
  Future<void> undo(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销这次采纳？'),
        content: const Text('只还原当时采纳的字段，其他内容保持不变。如果这些字段后来又改过，将停止撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.store.undoAdoption(id);
    } catch (e) {
      if (mounted) error = e is FormatException ? e.message : '撤销未完成，请重试';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.store.adoptionHistory(widget.book);
    return Scaffold(
      appBar: AppBar(title: const Text('采纳历史与撤销')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('每次采纳都保存前后内容。历史仅保存在本机，并随完整备份迁移。'),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('还没有采纳记录。对照原作后，选择需要的字段即可。'),
            ),
          for (final r in history)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text((r['before'] as Json)['title'] as String),
              subtitle: Text(
                '${DateTime.fromMillisecondsSinceEpoch(r['at'] as int).toString().substring(0, 16)} · ${widget.store.settings.containsKey('adoptionUndo:${r['id']}') ? '已撤销' : '已采纳'}',
              ),
              children: [
                for (final k in (r['fields'] as List).cast<String>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          comparisonFields[k]!,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          '采纳前',
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                        SelectableText((r['before'] as Json)[k] as String),
                        const SizedBox(height: 8),
                        const Text(
                          '采纳后',
                          style: TextStyle(color: Color(0xff2878f0)),
                        ),
                        SelectableText((r['after'] as Json)[k] as String),
                      ],
                    ),
                  ),
                OutlinedButton(
                  onPressed:
                      busy ||
                          widget.store.settings.containsKey(
                            'adoptionUndo:${r['id']}',
                          )
                      ? null
                      : () => undo(r['id'] as String),
                  child: const Text('撤销这次采纳'),
                ),
                const SizedBox(height: 16),
              ],
            ),
        ],
      ),
    );
  }
}
