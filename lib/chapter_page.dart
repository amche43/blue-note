import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'ink_page.dart';
import 'swipe_delete.dart';

String chapterName(Json q) => (q['chapter'] as String? ?? '').trim().isEmpty
    ? '未分章'
    : q['chapter'] as String;
List<String> notebookChapters(StudyStore store, String book) {
  final raw = store.settings['notebook:$book'];
  final stored = raw == null ? null : (jsonDecode(raw) as Json)['chapters'];
  return {
    if (stored is List) ...stored.whereType<String>(),
    ...store.questions.values
        .where((q) => q['notebookId'] == book && q['deleted'] == false)
        .map(chapterName),
  }.toList();
}

Future<void> createChapter(
  BuildContext context,
  StudyStore store,
  String book,
  String title,
) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建章节'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(hintText: '例如：第一章 极限与连续'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 350), c.dispose);
  if (name == null) return;
  try {
    final raw = store.settings['notebook:$book'];
    final meta = raw == null
        ? <String, dynamic>{'title': title, 'kind': 'question'}
        : jsonDecode(raw) as Json;
    final chapters = notebookChapters(store, book);
    if (chapters.length >= 300) throw const FormatException('章节较多，请建立另一学习本');
    await store.setting(
      'notebook:$book',
      jsonEncode({
        ...meta,
        'chapters': {...chapters, name}.toList(),
      }),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('章节未保存：$e')));
    }
  }
}

class ChapterPage extends StatefulWidget {
  final StudyStore store;
  final String book, title, chapter;
  final Future<void> Function(Lesson) openLesson;
  const ChapterPage({
    super.key,
    required this.store,
    required this.book,
    required this.title,
    required this.chapter,
    required this.openLesson,
  });
  @override
  State<ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<ChapterPage> {
  String query = '';
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

  Future<void> create() async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => InkPage(
          store: widget.store,
          notebookId: widget.book,
          notebookTitle: widget.title,
          chapter: widget.chapter == '未分章' ? '' : widget.chapter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        widget.store.questions.entries
            .where(
              (e) =>
                  e.value['deleted'] == false &&
                  e.value['notebookId'] == widget.book &&
                  chapterName(e.value) == widget.chapter &&
                  (e.value['title'] as String).toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (a, b) => (int.tryParse(a.value['questionNumber'] as String) ?? 0)
                .compareTo(
                  int.tryParse(b.value['questionNumber'] as String) ?? 0,
                ),
          );
    return Scaffold(
      backgroundColor: const Color(0xfff8fbff),
      appBar: AppBar(title: Text(widget.chapter)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.draw_outlined),
        label: const Text('新题目'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              Text(
                widget.title,
                style: const TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '查找这一章的题目',
                ),
              ),
              const SizedBox(height: 16),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.auto_stories_outlined,
                        size: 48,
                        color: Color(0xff2878f0),
                      ),
                      const SizedBox(height: 16),
                      Text(query.isEmpty ? '这一章还没有题目，从一页画布开始吧。' : '没有匹配的题目'),
                      TextButton(onPressed: create, child: const Text('创建题目')),
                    ],
                  ),
                ),
              for (final e in entries)
                SwipeDelete(
                  key: ValueKey(e.key),
                  onDelete: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除这道题？'),
                        content: Text(e.value['title'] as String),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('确认删除'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      try {
                        await widget.store.deleteQuestion(e.key);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('删除未完成，请重试')),
                          );
                        }
                      }
                    }
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xffe9f2ff),
                      child: Text(e.value['questionNumber'] as String),
                    ),
                    title: Text(e.value['title'] as String),
                    subtitle: Text(
                      (e.value['canvas'] as String? ?? '').isEmpty
                          ? '题目与学习记录'
                          : '手写画布 · 可继续编辑',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InkPage(store: widget.store, id: e.key),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
