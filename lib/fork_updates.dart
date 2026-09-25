import 'dart:convert';
import 'package:flutter/material.dart';
import 'community.dart';
import 'domain.dart';
import 'store.dart';
import 'ink_page.dart';
import 'learning_fields.dart';
import 'adoption_page.dart';

String comparisonText(Json? q, String key) => (q?[key] as String? ?? '').trim();
bool sameLearning(Json a, Json b) => comparisonFields.keys.every(
  (k) => comparisonText(a, k) == comparisonText(b, k),
);

class ForkChange {
  final String origin;
  final Json? before, current, mine;
  final String? localId;
  ForkChange(this.origin, this.before, this.current, this.mine, this.localId);
  String get status => before == null
      ? '原作新增'
      : current == null
      ? '原作已撤回'
      : sameLearning(before!, current!)
      ? '原作未变'
      : '原作已修改';
  bool get changed => status != '原作未变';
  bool get mineChanged =>
      before != null && mine != null && !sameLearning(before!, mine!);
  String get title =>
      (current ?? before ?? mine)?['title'] as String? ?? '学习条目';
}

List<ForkChange> compareFork(
  StudyStore store,
  String book,
  Json baseline,
  Json latest,
) {
  Map<String, Json> entries(Json value) => {
    for (final p in (value['items'] as List).cast<Json>())
      p['id'] as String: p['question'] as Json,
  };
  final before = entries(baseline), current = entries(latest);
  final local = {
    for (final e in store.questions.entries.where(
      (e) => e.value['notebookId'] == book && e.value['deleted'] != true,
    ))
      e.value['origin'] as String: e,
  };
  return [
    for (final id in {...before.keys, ...current.keys})
      ForkChange(id, before[id], current[id], local[id]?.value, local[id]?.key),
  ];
}

class ForkUpdatesPage extends StatefulWidget {
  final StudyStore store;
  final String book;
  final CommunityClient? client;
  const ForkUpdatesPage({
    super.key,
    required this.store,
    required this.book,
    this.client,
  });
  @override
  State<ForkUpdatesPage> createState() => _ForkUpdatesPageState();
}

class _ForkUpdatesPageState extends State<ForkUpdatesPage> {
  Json? baseline, latest;
  bool loading = false, onlyChanges = true;
  String error = '';
  DateTime? checked;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final saved = widget.store.settings['fork:${widget.book}'];
      if (saved == null) throw const FormatException('没有找到派生来源，请恢复包含来源的完整备份。');
      baseline = jsonDecode(saved) as Json;
      final raw = widget.store.settings['community'];
      if (widget.client == null && raw == null) {
        throw const FormatException('请先在账号中连接本机社区，再查看原作更新。');
      }
      final client =
          widget.client ?? CommunityClient(CommunityClient.parse(raw!));
      final result = await client.request(
        'GET',
        '/v1/notebooks/${baseline!['source']}/source-snapshot',
      );
      if (result['source'] != baseline!['source']) {
        throw const FormatException('原作来源不匹配');
      }
      // Validate the comparison before presenting any update counts.
      compareFork(widget.store, widget.book, baseline!, result);
      if (mounted) {
        setState(() {
          latest = result;
          checked = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '暂时无法检查原作，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> details(ForkChange item) async {
    final fields = comparisonFields.keys
        .where(
          (k) =>
              comparisonText(item.before, k) !=
                  comparisonText(item.current, k) ||
              comparisonText(item.before, k) != comparisonText(item.mine, k),
        )
        .toList();
    final edit = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        maxChildSize: .95,
        minChildSize: .4,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          children: [
            Text(item.title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${item.status} · ${item.mineChanged ? '你也修改过' : '自己的版本独立保存'}',
              style: const TextStyle(color: Color(0xff2878f0)),
            ),
            const SizedBox(height: 16),
            if (fields.isEmpty) const Text('内容与派生时一致。'),
            for (final k in fields) ...[
              Text(
                comparisonFields[k]!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              version('派生时的原作', item.before, k),
              version('现在的原作', item.current, k),
              version('我的版本', item.mine, k),
              const Divider(height: 28),
            ],
            const Text('公式以原始 LaTeX 展示。确认选择字段后才会采纳，自己的理解由自己保留。'),
            if (item.localId != null && item.current != null)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'adopt'),
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('选择性采纳原作内容'),
              ),
            if (item.localId != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑我的版本'),
                ),
              ),
          ],
        ),
      ),
    );
    if (edit == 'adopt' &&
        mounted &&
        item.localId != null &&
        item.current != null) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AdoptionPage(
            store: widget.store,
            lesson: item.localId!,
            before: item.mine!,
            incoming: item.current!,
          ),
        ),
      );
      if (mounted) setState(() {});
    }
    if (edit == 'edit' && mounted && item.localId != null) {
      await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => InkPage(store: widget.store, id: item.localId),
        ),
      );
      if (mounted) setState(() {});
    }
  }

  Widget version(String label, Json? q, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 4),
        SelectableText(
          q == null
              ? '此版本中没有这条内容'
              : comparisonText(q, key).isEmpty
              ? '未填写'
              : comparisonText(q, key),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final rows = latest == null || baseline == null
        ? <ForkChange>[]
        : compareFork(widget.store, widget.book, baseline!, latest!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('原作更新与对照'),
        actions: [
          IconButton(
            tooltip: '采纳历史与撤销',
            icon: const Icon(Icons.history),
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AdoptionHistoryPage(
                    store: widget.store,
                    book: widget.book,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: '检查原作更新',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            baseline?['title'] as String? ?? '派生笔记本',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('对照派生时、现在的原作和自己的理解，让学习成果继续成长。'),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (latest != null) ...[
            Text(
              '新增 ${rows.where((r) => r.before == null).length} · 修改 ${rows.where((r) => r.status == '原作已修改').length} · 撤回 ${rows.where((r) => r.current == null).length}',
              style: const TextStyle(
                color: Color(0xff2878f0),
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '检查于 ${checked!.toLocal().toString().substring(0, 16)} · 相对最初派生版本',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('只看原作变化'),
              value: onlyChanges,
              onChanged: (v) => setState(() => onlyChanges = v),
            ),
            if (onlyChanges && !rows.any((r) => r.changed))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('原作暂未变化，你可以继续完善自己的理解。'),
              ),
            for (final row in rows.where((r) => !onlyChanges || r.changed))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row.current == null
                      ? Icons.remove_circle_outline
                      : row.before == null
                      ? Icons.add_circle_outline
                      : Icons.compare_arrows,
                  color: const Color(0xff2878f0),
                ),
                title: Text(row.title),
                subtitle: Text(
                  '${row.status}${row.mineChanged ? ' · 你也修改过' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => details(row),
              ),
          ],
        ],
      ),
    );
  }
}
