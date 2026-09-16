import 'package:flutter/material.dart';
import 'community.dart';
import 'domain.dart';

const improvementFields = {
  'answer': '正确解析',
  'trigger': '关键突破点',
  'action': '解题方法',
  'conditions': '使用条件',
  'pitfall': '易错提醒',
};

class ImprovementsPage extends StatefulWidget {
  final CommunityClient client;
  final String bookId;
  final String? initialProposalId;
  const ImprovementsPage({
    super.key,
    required this.client,
    required this.bookId,
    this.initialProposalId,
  });
  @override
  State<ImprovementsPage> createState() => _ImprovementsPageState();
}

class _ImprovementsPageState extends State<ImprovementsPage> {
  List<Json> items = [], entries = [];
  bool busy = false;
  String error = '';
  String get path => '/v1/notebooks/${widget.bookId}';
  @override
  void initState() {
    super.initState();
    run(load);
  }

  Future<void> load() async {
    final proposals = await widget.client.request('GET', '$path/improvements');
    final book = await widget.client.request('GET', path);
    if (mounted) {
      setState(() {
        items = (proposals['items'] as List).cast<Json>();
        entries = (book['items'] as List).cast<Json>();
      });
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await task();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '操作未确认完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> propose() async {
    final entry = await showModalBottomSheet<Json>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('选择要改进的条目')),
            ...entries.map(
              (e) => ListTile(
                title: Text(e['package']['question']['title'] as String),
                onTap: () => Navigator.pop(ctx, e),
              ),
            ),
          ],
        ),
      ),
    );
    if (entry == null || !mounted) return;
    await run(() async {
      final current = await widget.client.request(
        'GET',
        '/v1/questions/${entry['id']}',
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ImprovementEditor(
            client: widget.client,
            path: '$path/improvements',
            entry: current,
          ),
        ),
      );
      await load();
    });
  }

  Future<void> review(Json item, bool accept) async {
    final note = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(accept ? '接受这次改进？' : '说明拒绝原因'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(accept ? '接受后会更新公开条目，个人设备里已有的副本不会被覆盖。' : '让贡献者知道哪些地方还需要完善。'),
              TextField(
                controller: note,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: '处理说明'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, note.text),
            child: Text(accept ? '接受并合并' : '拒绝'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), note.dispose);
    if (value == null) return;
    await run(() async {
      await widget.client.request('PUT', '$path/improvements', {
        'id': item['id'],
        'status': accept ? 'accepted' : 'rejected',
        'note': value,
      });
      await load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('共同完善'),
      actions: [
        IconButton(
          onPressed: busy ? null : () => run(load),
          tooltip: '刷新改进',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          '让每一个好理解，成为大家的收获。',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text('提出解析或知识点修改，作者核对后合并。这里保留修改前后内容与处理记录。'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy || entries.isEmpty ? null : propose,
          icon: const Icon(Icons.edit_note),
          label: const Text('提交改进'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!busy && items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('还没有改进提案。发现更清晰的解法，就从这里开始。'),
          ),
        ...items.map(
          (i) => ExpansionTile(
            initiallyExpanded: widget.initialProposalId == i['id'],
            tilePadding: EdgeInsets.zero,
            title: Text(
              '${i['title']} · ${improvementFields[i['field']] ?? i['field']}',
            ),
            subtitle: Text(
              '${i['name']} · ${{'pending': '待核对', 'accepted': '已合并', 'rejected': '未采纳'}[i['status']]}',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  '修改理由\n${i['reason']}\n\n原文\n${i['before_text']}\n\n建议改为\n${i['after_text']}',
                ),
              ),
              if ((i['review_note'] as String? ?? '').isNotEmpty)
                Text('处理说明：${i['review_note']}'),
              if (i['canReview'] == 1 && i['status'] == 'pending')
                Row(
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => review(i, false),
                      child: const Text('拒绝'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: busy ? null : () => review(i, true),
                      child: const Text('接受改进'),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    ),
  );
}

class ImprovementEditor extends StatefulWidget {
  final CommunityClient client;
  final String path;
  final Json entry;
  const ImprovementEditor({
    super.key,
    required this.client,
    required this.path,
    required this.entry,
  });
  @override
  State<ImprovementEditor> createState() => _ImprovementEditorState();
}

class _ImprovementEditorState extends State<ImprovementEditor> {
  final after = TextEditingController(), reason = TextEditingController();
  String field = 'answer', error = '', rid = newId();
  bool busy = false;
  String get before =>
      widget.entry['package']['question'][field] as String? ?? '';
  @override
  void initState() {
    super.initState();
    after.text = before;
  }

  @override
  void dispose() {
    after.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.client.request('POST', widget.path, {
        'requestId': rid,
        'question': widget.entry['id'],
        'base': widget.entry['revision'],
        'field': field,
        'after': after.text.trim(),
        'reason': reason.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '提交未确认，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提交改进')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.entry['package']['question']['title'] as String,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: field,
          items: improvementFields.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: busy
              ? null
              : (v) => setState(() {
                  field = v!;
                  after.text = before;
                  rid = newId();
                }),
        ),
        const SizedBox(height: 16),
        const Text('原文', style: TextStyle(color: Colors.blueGrey)),
        SelectableText(before.isEmpty ? '尚未填写' : before),
        const SizedBox(height: 20),
        TextField(
          controller: after,
          enabled: !busy,
          minLines: 4,
          maxLines: 12,
          maxLength: field == 'answer' ? 18000 : 4000,
          onChanged: (_) => rid = newId(),
          decoration: const InputDecoration(labelText: '建议改为'),
        ),
        TextField(
          controller: reason,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          onChanged: (_) => rid = newId(),
          decoration: const InputDecoration(labelText: '为什么这样修改？'),
        ),
        const Text(
          '提交后，修改内容和理由会在此学习本公开，原文须经作者接受后才更新。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        if (error.isNotEmpty) Text(error),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? '正在提交…' : '提交给作者核对'),
        ),
      ],
    ),
  );
}
