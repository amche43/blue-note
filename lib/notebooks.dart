import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'question_editor.dart';
import 'fork_updates.dart';
import 'adoption_page.dart';

bool isKnowledgeBook(StudyStore store, String id) {
  final entries = store.questions.values.where((q) => q['notebookId'] == id);
  if (entries.isNotEmpty) {
    return entries.every((q) => q['contentKind'] == 'knowledge');
  }
  final raw = store.settings['notebook:$id'];
  return raw != null && (jsonDecode(raw) as Json)['kind'] == 'knowledge';
}

Map<String, String> notebooks(StudyStore store) {
  final result = <String, String>{};
  for (final q in store.questions.values) {
    if ((q['notebookId'] as String? ?? '').isNotEmpty) {
      result[q['notebookId'] as String] = q['notebookTitle'] as String;
    }
  }
  for (final e in store.settings.entries.where(
    (e) => e.key.startsWith('notebook:'),
  )) {
    result[e.key.substring(9)] =
        (jsonDecode(e.value) as Json)['title'] as String;
  }
  return result;
}

class NotebooksPage extends StatefulWidget {
  final StudyStore store;
  final bool knowledge;
  final String? initialBook;
  final Future<void> Function(Lesson) openLesson;
  const NotebooksPage({
    super.key,
    required this.store,
    required this.openLesson,
    this.knowledge = false,
    this.initialBook,
  });
  @override
  State<NotebooksPage> createState() => _NotebooksPageState();
}

class AllNotebooksPage extends StatefulWidget {
  final StudyStore store;
  final Future<void> Function(Lesson) openLesson;
  const AllNotebooksPage({
    super.key,
    required this.store,
    required this.openLesson,
  });
  @override
  State<AllNotebooksPage> createState() => _AllNotebooksPageState();
}

class _AllNotebooksPageState extends State<AllNotebooksPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的学习本')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索我的学习本',
          ),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
        const SizedBox(height: 16),
        if (notebooks(widget.store).isEmpty) const Text('还没有学习本。点击首页中央的加号创建。'),
        ...notebooks(widget.store).entries
            .where((e) => e.value.contains(query))
            .map(
              (e) => ListTile(
                leading: Icon(
                  isKnowledgeBook(widget.store, e.key)
                      ? Icons.style_outlined
                      : Icons.menu_book_outlined,
                ),
                title: Text(e.value),
                subtitle: Text(
                  '${widget.store.questions.values.where((q) => q['notebookId'] == e.key && q['deleted'] == false).length} 条内容',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotebooksPage(
                        store: widget.store,
                        knowledge: isKnowledgeBook(widget.store, e.key),
                        initialBook: e.key,
                        openLesson: widget.openLesson,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
      ],
    ),
  );
}

class _NotebooksPageState extends State<NotebooksPage> {
  String? selected;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    selected = widget.initialBook;
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

  Future<void> create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建错题本'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '名称，例如：我的高数错题本'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (name == null || !mounted) return;
    setState(() => busy = true);
    try {
      final id = 'book-${newId()}';
      await widget.store.setting(
        'notebook:$id',
        jsonEncode({
          'title': name,
          'kind': widget.knowledge ? 'knowledge' : 'question',
        }),
      );
      if (mounted) setState(() => selected = id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('错题本未保存，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = notebooks(widget.store)
      ..removeWhere(
        (id, title) => isKnowledgeBook(widget.store, id) != widget.knowledge,
      );
    final list =
        widget.store.questions.entries
            .where(
              (e) =>
                  e.value['deleted'] == false &&
                  e.value['notebookId'] == selected,
            )
            .toList()
          ..sort(
            (a, b) => int.parse(
              a.value['questionNumber'] as String,
            ).compareTo(int.parse(b.value['questionNumber'] as String)),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected == null
              ? (widget.knowledge ? '必备知识点本' : '我的错题本')
              : books[selected] ?? '错题本',
        ),
        leading: selected == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => selected = null),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.knowledge
                ? '记录定理、端口号、固定搭配等必记内容。先回想，再展开核对。默认私有。'
                : '错题本默认私有。每题有固定题号，删除前面的题也不会重新编号。',
          ),
          const SizedBox(height: 16),
          if (selected == null) ...[
            FilledButton.icon(
              onPressed: busy ? null : create,
              icon: const Icon(Icons.add),
              label: Text(widget.knowledge ? '新建知识点本' : '新建错题本'),
            ),
            ...books.entries.map(
              (e) => Card(
                child: ListTile(
                  title: Text(e.value),
                  subtitle: Text(
                    '${widget.store.questions.values.where((q) => q['notebookId'] == e.key && q['deleted'] == false).length} 道题',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => selected = e.key),
                ),
              ),
            ),
            if (books.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('先建一本，再慢慢收集让你卡住的题目。'),
              ),
          ] else ...[
            if (widget.store.settings.containsKey('fork:$selected'))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('查看原作更新与对照'),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ForkUpdatesPage(store: widget.store, book: selected!),
                    ),
                  ),
                ),
              ),
            if (widget.store.settings.containsKey('fork:$selected'))
              TextButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdoptionHistoryPage(
                      store: widget.store,
                      book: selected!,
                    ),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('采纳历史与撤销'),
              ),
            FilledButton.icon(
              onPressed: () => Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionEditor(
                    store: widget.store,
                    notebookId: selected,
                    notebookTitle: books[selected],
                    knowledge: widget.knowledge,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(widget.knowledge ? '添加知识卡片' : '在这本里添加题目'),
            ),
            ...list.map(
              (e) => Card(
                child: ListTile(
                  title: Text(
                    '第${e.value['questionNumber']}条 · ${e.value['title']}',
                  ),
                  subtitle: Text(e.value['subject'] as String),
                  onTap: () => widget.openLesson(
                    widget.store.lessons.firstWhere((l) => l.id == e.key),
                  ),
                ),
              ),
            ),
            const Text('分享入口在“我的 → 共享题库 → 发布我的题目”。只有确认发布的题目会出现在公开错题本中。'),
          ],
        ],
      ),
    );
  }
}
