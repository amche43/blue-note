import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'entry_composer.dart';
import 'question_editor.dart';

class LocalDraft {
  final String key, raw;
  final Json? data;
  final int at;
  LocalDraft(this.key, this.raw, this.data, this.at);
  factory LocalDraft.read(String key, String raw) {
    try {
      final value = jsonDecode(raw) as Json;
      final data = value['data'] as Json;
      if (data['fields'] is! Json ||
          (data['fields'] as Json).values.any((v) => v is! String)) {
        throw const FormatException('fields');
      }
      final at = value['at'];
      if (at is! int || at < 0 || at > 8640000000000000) {
        throw const FormatException('time');
      }
      if (data['book'] != null && data['book'] is! String) {
        throw const FormatException('book');
      }
      if (key.startsWith('editDraft:composer-') &&
          (!['question', 'knowledge'].contains(data['kind']) ||
              data['step'] is! int ||
              (data['step'] as int) < 0 ||
              (data['step'] as int) > 2)) {
        throw const FormatException('composer');
      }
      return LocalDraft(key, raw, data, value['at'] as int);
    } catch (_) {
      return LocalDraft(key, raw, null, 0);
    }
  }
  Json get fields => data?['fields'] as Json? ?? {};
  String get title {
    final t = (fields['title'] as String? ?? '').trim();
    if (t.isNotEmpty) return t;
    final p = (fields['prompt'] as String? ?? '').trim();
    return p.isEmpty ? '未命名草稿' : p.split('\n').first;
  }

  bool get knowledge => (data?['kind'] ?? fields['contentKind']) == 'knowledge';
  String get book => (data?['book'] ?? fields['notebookId'] ?? '') as String;
  String get savedAt => at <= 0
      ? '保存时间未知'
      : DateTime.fromMillisecondsSinceEpoch(at).toString().substring(0, 16);
}

List<LocalDraft> localDrafts(StudyStore store) =>
    store.settings.entries
        .where((e) => e.key.startsWith('editDraft:'))
        .map((e) => LocalDraft.read(e.key, e.value))
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));

class DraftsPage extends StatefulWidget {
  final StudyStore store;
  const DraftsPage({super.key, required this.store});
  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  String query = '', filter = 'all', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(update);
    super.dispose();
  }

  String bookName(LocalDraft draft) {
    if (draft.book.isEmpty) return '尚未选择学习本';
    final raw = widget.store.settings['notebook:${draft.book}'];
    if (raw != null) {
      try {
        return (jsonDecode(raw) as Json)['title'] as String;
      } catch (_) {}
    }
    return (draft.fields['notebookTitle'] as String? ?? '').isEmpty
        ? '原学习本暂不可用'
        : draft.fields['notebookTitle'] as String;
  }

  Future<void> resume(LocalDraft draft) async {
    if (busy) return;
    setState(() => error = '');
    try {
      if (widget.store.settings[draft.key] != draft.raw) {
        throw const FormatException('草稿刚刚发生变化，请重新打开');
      }
      if (draft.data == null) throw const FormatException('这份草稿暂时无法读取，未修改原记录。');
      final suffix = draft.key.substring('editDraft:'.length);
      Widget page;
      if (suffix == 'composer-question' || suffix == 'composer-knowledge') {
        page = EntryComposer(
          store: widget.store,
          initialKind: suffix.substring('composer-'.length),
        );
      } else if (RegExp(r'^user-[a-f0-9]{32}$').hasMatch(suffix)) {
        if (!widget.store.questions.containsKey(suffix)) {
          throw const FormatException('找不到原条目，草稿仍保留。请先恢复对应题库。');
        }
        page = QuestionEditor(store: widget.store, id: suffix);
      } else {
        final match = RegExp(r'^new-(true|false)-(.*)$').firstMatch(suffix);
        if (match == null) throw const FormatException('暂不支持这个草稿入口，原记录仍保留。');
        final initialBook = match[2]!;
        page = QuestionEditor(
          store: widget.store,
          knowledge: match[1] == 'true',
          notebookId: initialBook,
          notebookTitle:
              (draft.data!['base'] as Json?)?['notebookTitle'] as String?,
        );
      }
      await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '草稿暂时无法打开，原记录仍保留。',
        );
      }
    }
  }

  Future<void> remove(LocalDraft draft) async {
    if (busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这份草稿？'),
        content: Text(
          '将删除「${draft.title}」尚未正式保存的内容和其中的识别图片。已正式保存的题目不受影响。此操作不能撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除草稿'),
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
      final count = await widget.store.db.delete(
        'settings',
        where: 'key=? AND value=?',
        whereArgs: [draft.key, draft.raw],
      );
      await widget.store.refresh();
      if (count == 0) throw const FormatException('草稿已更新或已删除，请重新核对');
    } catch (e) {
      if (mounted) error = e is FormatException ? e.message : '删除未完成，请重试';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = localDrafts(widget.store);
    final list = all
        .where(
          (d) =>
              (filter == 'all' || (filter == 'knowledge') == d.knowledge) &&
              ('${d.title} ${d.fields['prompt'] ?? ''} ${bookName(d)}')
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('我的草稿箱')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${all.length} 份未完成的思考',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            '先留下，再慢慢完善。草稿仅在当前设备，正式保存后才进入学习本。',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索标题、正文或学习本',
            ),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('全部')),
              ButtonSegment(value: 'question', label: Text('题目')),
              ButtonSegment(value: 'knowledge', label: Text('知识卡片')),
            ],
            selected: {filter},
            onSelectionChanged: (v) => setState(() => filter = v.single),
          ),
          const SizedBox(height: 16),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Text(
                all.isEmpty ? '还没有草稿。录入内容时会自动暂存，也可以选择保留草稿后退出。' : '没有找到匹配的草稿。',
              ),
            ),
          for (final d in list)
            Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.knowledge ? Icons.lightbulb_outline : Icons.edit_note,
                    color: const Color(0xff2878f0),
                  ),
                  title: Text(
                    d.data == null ? '无法读取的草稿' : d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${bookName(d)}\n${d.savedAt}${d.data?['capture'] != null ? ' · 含识别记录' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  onTap: busy ? null : () => resume(d),
                  trailing: IconButton(
                    tooltip: '删除草稿',
                    onPressed: busy ? null : () => remove(d),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          const SizedBox(height: 24),
          const Text(
            '迁移设备前，请先正式保存需要保留的内容。草稿暂不包含在完整备份中。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
