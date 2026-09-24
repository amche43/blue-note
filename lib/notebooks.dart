import 'notebook_actions.dart';
import 'dart:convert';
import 'swipe_delete.dart';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'chapter_page.dart';
import 'fork_updates.dart';
import 'adoption_page.dart';
import 'notebook_ui.dart';
import 'brand.dart';
import 'ink_page.dart';

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
  return {
    for (final id in orderedIds(store, 'books', result.keys)) id: result[id]!,
  };
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
  final bool initialLoosePages;
  final Future<void> Function(Lesson) openLesson;
  const AllNotebooksPage({
    super.key,
    required this.store,
    required this.openLesson,
    this.initialLoosePages = false,
  });
  @override
  State<AllNotebooksPage> createState() => _AllNotebooksPageState();
}

class _AllNotebooksPageState extends State<AllNotebooksPage> {
  String query = '', filter = '我创建的';
  bool searching = false, loosePages = false;
  @override
  void initState() {
    super.initState();
    loosePages = widget.initialLoosePages;
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

  Future<void> openBook(String id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NotebooksPage(
          store: widget.store,
          initialBook: id,
          openLesson: widget.openLesson,
        ),
      ),
    );
  }

  Future<void> create() async {
    final names = notebooks(widget.store).values.toSet();
    var n = 1;
    while (names.contains('新建笔记本$n')) {
      n++;
    }
    final id = 'book-${newId()}';
    await widget.store.setting(
      'notebook:$id',
      jsonEncode({'title': '新建笔记本$n', 'kind': 'question'}),
    );
    if (mounted) {
      final name = await requestItemName(context, '新建笔记本$n');
      if (name != null) {
        await widget.store.setting(
          'notebook:$id',
          jsonEncode({'title': name, 'kind': 'question'}),
        );
      }
      if (mounted) await openBook(id);
    }
  }

  bool matches(String id, String type) {
    if (type == '我创建的') return !widget.store.settings.containsKey('fork:$id');
    if (type == '已上传社区') {
      return widget.store.questions.entries.any(
        (e) =>
            e.value['notebookId'] == id &&
            widget.store.settings.containsKey('publication:${e.key}'),
      );
    }
    if (type == '待同步') {
      return widget.store.questions.entries.any((e) {
        if (e.value['notebookId'] != id || e.value['deleted'] == true) {
          return false;
        }
        final raw = widget.store.settings['publication:${e.key}'];
        if (raw == null) return false;
        final revisions =
            widget.store.events
                .where((v) => v.type == 'question' && v.lessonId == e.key)
                .toList()
              ..sort(compareEvents);
        return revisions.isNotEmpty &&
            (jsonDecode(raw) as Json)['revision'] != revisions.last.id;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final all = notebooks(widget.store).entries.toList();
    final visible = all
        .where(
          (b) =>
              (filter == '全部' || matches(b.key, filter)) &&
              b.value.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      backgroundColor: notebookPaper,
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.maybePop(context)),
        backgroundColor: notebookPaper,
        title: const Text('笔记本'),
        actions: [
          IconButton(
            tooltip: '搜索笔记本',
            onPressed: () => setState(() => searching = !searching),
            icon: const Icon(Icons.search),
          ),
          NotebookAddButton(
            onPressed: loosePages
                ? () => Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InkPage(store: widget.store),
                    ),
                  )
                : create,
            tooltip: loosePages ? '新建便笺' : '新建笔记本',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            children: [
              BlueAvatar(
                photo: widget.store.settings['avatarImage'],
                index:
                    int.tryParse(widget.store.settings['avatar'] ?? '0') ?? 0,
                width: 52,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的知识本',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: notebookInk,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '记录知识，遇见更大的自己',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in ['我创建的', '已上传社区', '参与编辑', '待同步', '只读分享', '全部'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() => filter = f),
                      child: Container(
                        width: 100,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: filter == f
                              ? const Color(0xffe0edff)
                              : const Color(0xffeef3f9),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Text(
                              f,
                              style: TextStyle(
                                color: filter == f
                                    ? const Color(0xff1263ff)
                                    : Colors.blueGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${f == '全部' ? all.length : all.where((b) => matches(b.key, f)).length}',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索笔记本名称',
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (!loosePages && visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_stories_outlined,
                    size: 44,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(height: 16),
                  Text(all.isEmpty ? '从第一本笔记开始。' : '这里还没有匹配的笔记本'),
                  TextButton(
                    onPressed: all.isEmpty
                        ? create
                        : () => setState(() {
                            filter = '全部';
                            query = '';
                          }),
                    child: Text(all.isEmpty ? '创建笔记本' : '查看全部'),
                  ),
                ],
              ),
            ),
          if (widget.store.questions.values.any(
            (q) => q['notebookId'] == '' && q['deleted'] == false,
          )) ...[
            const Text('随手写下的未归档画布', style: TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 12),
            for (final e in widget.store.questions.entries.where(
              (e) => e.value['notebookId'] == '' && e.value['deleted'] == false,
            ))
              NotebookCard(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(e.value['title'] as String),
                  onTap: () => Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InkPage(store: widget.store, id: e.key),
                    ),
                  ),
                ),
              ),
            if (!widget.store.questions.values.any(
              (q) => q['notebookId'] == '' && q['deleted'] == false,
            ))
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有便笺，点击 + 随手记录。'),
              ),
          ],
          if (!loosePages)
            NotebookReorderList(
              onReorder: (a, b) => reorderItems(
                widget.store,
                'books',
                visible.map((e) => e.key).toList(),
                a,
                b,
              ),
              children: [
                for (final b in visible)
                  SwipeDelete(
                    key: ValueKey(b.key),
                    onUpload: () => uploadEntries(
                      context,
                      widget.store,
                      widget.store.questions.entries
                          .where((e) => e.value['notebookId'] == b.key)
                          .map((e) => e.key)
                          .toList(),
                    ),
                    onDelete: () async {
                      await confirmDeleteNotebook(context, widget.store, b.key);
                    },
                    child: NotebookCard(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: NotebookCover(
                          index: all.indexOf(b),
                          state: bookIconState(widget.store, b.key),
                        ),
                        title: Text(
                          b.value,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: notebookInk,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${notebookChapters(widget.store, b.key).length} 章 · ${matches(b.key, '已上传社区')
                                ? '有已发布知识页'
                                : widget.store.settings.containsKey('fork:${b.key}')
                                ? '我的派生版本'
                                : '我创建的'}',
                            style: const TextStyle(color: Colors.blueGrey),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openBook(b.key),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NotebooksPageState extends State<NotebooksPage> {
  String? selected;
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

  bool chapterSearch = false;
  String chapterQuery = '';
  Future<void> renameBook() async {
    final c = TextEditingController(
      text: notebooks(widget.store)[selected] ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('笔记本名称'),
        content: TextField(controller: c, autofocus: true, maxLength: 80),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final key = 'notebook:$selected';
    final meta = jsonDecode(widget.store.settings[key] ?? '{}') as Json;
    final entries = widget.store.questions.entries
        .where((e) => e.value['notebookId'] == selected)
        .toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    await widget.store.merge(
      [
        for (final e in entries)
          StudyEvent(
            id: newId(),
            lessonId: e.key,
            type: 'question',
            at: widget.store.events
                .where((v) => v.lessonId == e.key)
                .fold<int>(now, (a, v) => v.at >= a ? v.at + 1 : a),
            payload: {...e.value, 'notebookTitle': name},
          ),
      ],
      expectedQuestions: {for (final e in entries) e.key: e.value},
      removeSettings: [key],
      localSettings: {
        key: jsonEncode({...meta, 'title': name}),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return AllNotebooksPage(
        store: widget.store,
        openLesson: widget.openLesson,
      );
    }
    final title = notebooks(widget.store)[selected] ?? '笔记本';
    final chapters = notebookChapters(widget.store, selected!);

    chapters.removeWhere(
      (c) => !c.toLowerCase().contains(chapterQuery.toLowerCase()),
    );
    return Scaffold(
      backgroundColor: notebookPaper,
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.maybePop(context)),
        backgroundColor: notebookPaper,
        title: InkWell(
          onTap: renameBook,
          child: Row(
            children: [
              const NotebookCover(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        actions: [
          NotebookAddButton(
            onPressed: () =>
                createChapter(context, widget.store, selected!, title),
            tooltip: '新建章节',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          if (chapterSearch)
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => chapterQuery = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索章节名称',
              ),
            ),

          Row(
            children: [
              Expanded(
                child: Text(
                  '${chapters.length} 个章节',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          NotebookReorderList(
            onReorder: (a, b) => reorderItems(
              widget.store,
              'chapters:$selected',
              chapters,
              a,
              b,
            ),
            children: [
              for (var i = 0; i < chapters.length; i++)
                SwipeDelete(
                  key: ValueKey(chapters[i]),
                  onDelete: () => deleteChapter(
                    context,
                    widget.store,
                    selected!,
                    chapters[i],
                  ),
                  onUpload: () => uploadEntries(
                    context,
                    widget.store,
                    widget.store.questions.entries
                        .where(
                          (e) =>
                              e.value['notebookId'] == selected &&
                              chapterName(e.value) == chapters[i],
                        )
                        .map((e) => e.key)
                        .toList(),
                  ),
                  child: NotebookCard(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: NotebookCover(
                        index: i,
                        contentIcon:
                            widget.store.questions.values.any(
                              (q) =>
                                  q['deleted'] == false &&
                                  q['notebookId'] == selected &&
                                  chapterName(q) == chapters[i],
                            )
                            ? Icons.description_outlined
                            : null,
                        state: bookIconState(
                          widget.store,
                          selected!,
                          chapter: chapters[i],
                        ),
                        number: '${i + 1}'.padLeft(2, '0'),
                      ),
                      title: Text(
                        chapters[i],
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: notebookInk,
                        ),
                      ),
                      subtitle: Text(
                        '${widget.store.questions.values.where((q) => q['deleted'] == false && q['notebookId'] == selected && chapterName(q) == chapters[i]).length} 个知识页',
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChapterPage(
                            store: widget.store,
                            book: selected!,
                            title: title,
                            chapter: chapters[i],
                            openLesson: widget.openLesson,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (chapters.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('点击右上角 + 创建第一章。', textAlign: TextAlign.center),
            ),
          const SizedBox(height: 24),
          if (widget.store.settings.containsKey('fork:$selected')) ...[
            TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ForkUpdatesPage(store: widget.store, book: selected!),
                ),
              ),
              child: const Text('查看原作更新与对照'),
            ),
            TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AdoptionHistoryPage(store: widget.store, book: selected!),
                ),
              ),
              child: const Text('采纳历史与撤销'),
            ),
          ],
        ],
      ),
    );
  }
}
