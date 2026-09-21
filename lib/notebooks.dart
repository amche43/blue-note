import 'dart:convert';
import 'swipe_delete.dart';
import 'community.dart';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'chapter_page.dart';
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
    if (q['deleted'] == false &&
        (q['notebookId'] as String? ?? '').isNotEmpty) {
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

Future<bool> confirmDeleteNotebook(
  BuildContext context,
  StudyStore store,
  String id,
) async {
  final title = notebooks(store)[id] ?? '学习本';
  final count = store.questions.values
      .where((q) => q['notebookId'] == id && q['deleted'] == false)
      .length;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除这本学习本？'),
      content: Text(
        '将从本机移除「$title」及其中 $count 条内容。草稿和历史记录保留；已经发布的社区内容不会下架。删除前可先导出备份。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('保留'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffd83a49),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认删除'),
        ),
      ],
    ),
  );
  if (yes != true) return false;
  try {
    await store.deleteNotebook(id);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除未完成，请重试')));
    }
    return false;
  }
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
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('新建学习本'),
          onPressed: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => NotebooksPage(
                  store: widget.store,
                  openLesson: widget.openLesson,
                ),
              ),
            );
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 12),
        if (notebooks(widget.store).isEmpty) const Text('还没有学习本。从第一本开始吧。'),
        ...notebooks(widget.store).entries
            .where((e) => e.value.contains(query))
            .map(
              (e) => SwipeDelete(
                key: ValueKey(e.key),
                onDelete: () async {
                  await confirmDeleteNotebook(context, widget.store, e.key);
                  if (mounted) setState(() {});
                },
                child: ListTile(
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
        title: Text(widget.knowledge ? '新建知识点本' : '新建错题本'),
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
              (e) => SwipeDelete(
                key: ValueKey(e.key),
                onDelete: () async {
                  await confirmDeleteNotebook(context, widget.store, e.key);
                },
                child: Card(
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
              onPressed: () async {
                await createChapter(
                  context,
                  widget.store,
                  selected!,
                  books[selected]!,
                );
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新建章节'),
            ),
            for (final chapter in notebookChapters(widget.store, selected!))
              ListTile(
                key: ValueKey('$selected:$chapter'),
                leading: const Icon(
                  Icons.folder_outlined,
                  color: Color(0xff2878f0),
                ),
                title: Text(chapter),
                subtitle: Text(
                  '${list.where((e) => chapterName(e.value) == chapter).length} 条内容',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChapterPage(
                      store: widget.store,
                      book: selected!,
                      title: books[selected]!,
                      chapter: chapter,
                      openLesson: widget.openLesson,
                    ),
                  ),
                ),
              ),
            if (notebookChapters(widget.store, selected!).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('先创建第一章，再开始记录题目。'),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.public),
              label: const Text('上传至社区 / 管理已发布内容'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityPage(store: widget.store),
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除学习本'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xffd83a49),
              ),
              onPressed: () async {
                if (await confirmDeleteNotebook(
                      context,
                      widget.store,
                      selected!,
                    ) &&
                    mounted) {
                  setState(() => selected = null);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
