import 'notebook_actions.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'ink_page.dart';
import 'swipe_delete.dart';
import 'notebook_ui.dart';

String chapterName(Json q) => (q['chapter'] as String? ?? '').trim().isEmpty
    ? '未分章'
    : q['chapter'] as String;
List<String> notebookChapters(StudyStore store, String book) {
  final raw = store.settings['notebook:$book'];
  final stored = raw == null ? null : (jsonDecode(raw) as Json)['chapters'];
  return orderedIds(
    store,
    'chapters:$book',
    {
      if (stored is List) ...stored.whereType<String>(),
      ...store.questions.values
          .where((q) => q['notebookId'] == book && q['deleted'] == false)
          .map(chapterName),
    }.toList(),
  );
}

Future<void> createChapter(
  BuildContext context,
  StudyStore store,
  String book,
  String title,
) async {
  final existing = notebookChapters(store, book);
  var number = 1;
  while (existing.contains('新建章节$number')) {
    number++;
  }
  final name = '新建章节$number';
  try {
    final raw = store.settings['notebook:$book'];
    final meta = raw == null
        ? <String, dynamic>{'title': title, 'kind': 'question'}
        : jsonDecode(raw) as Json;
    final chapters = notebookChapters(store, book);
    if (chapters.length >= 300) throw const FormatException('章节较多，请建立另一笔记本');
    await store.setting(
      'notebook:$book',
      jsonEncode({
        ...meta,
        'chapters': {...chapters, name}.toList(),
      }),
    );
    if (context.mounted) {
      final renamed = await requestItemName(context, name);
      if (renamed != null && !chapters.contains(renamed)) {
        await store.setting(
          'notebook:$book',
          jsonEncode({
            ...meta,
            'chapters': [...chapters, renamed],
          }),
        );
      }
    }
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
  late String currentChapter;
  late TextEditingController chapterTitle;
  @override
  void initState() {
    super.initState();
    currentChapter = widget.chapter;
    chapterTitle = TextEditingController(text: currentChapter);
    widget.store.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    chapterTitle.dispose();
    widget.store.removeListener(update);
    super.dispose();
  }

  Future<void> rename(String value) async {
    final name = value.trim();
    if (name.isEmpty || name == currentChapter) {
      chapterTitle.text = currentChapter;
      return;
    }
    try {
      final chapters = notebookChapters(widget.store, widget.book);
      if (chapters.contains(name)) throw const FormatException('已有同名章节，请换一个名称');
      final raw = widget.store.settings['notebook:${widget.book}'];
      final meta = raw == null
          ? <String, dynamic>{'title': widget.title, 'kind': 'question'}
          : jsonDecode(raw) as Json;
      final entries = widget.store.questions.entries
          .where(
            (e) =>
                e.value['deleted'] == false &&
                e.value['notebookId'] == widget.book &&
                chapterName(e.value) == currentChapter,
          )
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
              payload: {...e.value, 'chapter': name},
            ),
        ],
        expectedQuestions: {for (final e in entries) e.key: e.value},
        removeSettings: [
          'notebook:${widget.book}',
          'order:chapters:${widget.book}',
          'color:chapter:${widget.book}:$currentChapter',
        ],
        localSettings: {
          if (widget.store.settings.containsKey(
            'color:chapter:${widget.book}:$currentChapter',
          ))
            'color:chapter:${widget.book}:$name': widget
                .store
                .settings['color:chapter:${widget.book}:$currentChapter']!,
          'order:chapters:${widget.book}': jsonEncode(
            chapters.map((c) => c == currentChapter ? name : c).toList(),
          ),
          'notebook:${widget.book}': jsonEncode({
            ...meta,
            'chapters': chapters
                .map((c) => c == currentChapter ? name : c)
                .toList(),
          }),
        },
      );
      if (mounted) setState(() => currentChapter = name);
    } catch (e) {
      chapterTitle.text = currentChapter;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('改名未保存：$e')));
      }
    }
  }

  String updated(String id) {
    final records =
        widget.store.events
            .where((e) => e.lessonId == id && e.type == 'question')
            .toList()
          ..sort(compareEvents);
    return records.isEmpty ? '' : notebookUpdated(records.last.at);
  }

  Future<void> create() async {
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => InkPage(
          store: widget.store,
          notebookId: widget.book,
          notebookTitle: widget.title,
          chapter: currentChapter == '未分章' ? '' : currentChapter,
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
                  chapterName(e.value) == currentChapter &&
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
    final order = orderedIds(
      widget.store,
      'pages:${widget.book}',
      entries.map((e) => e.key),
    );
    entries.sort(
      (a, b) => order.indexOf(a.key).compareTo(order.indexOf(b.key)),
    );
    return Scaffold(
      backgroundColor: notebookPaper,
      appBar: AppBar(
        backgroundColor: notebookPaper,
        actions: [NotebookAddButton(onPressed: create, tooltip: '新建页面')],
        title: Row(
          children: [
            NotebookCover(
              index: itemColor(
                widget.store,
                'chapter:${widget.book}:$currentChapter',
                parent: widget.book,
              ),
              number:
                  '${notebookChapters(widget.store, widget.book).indexOf(currentChapter) + 1}'
                      .padLeft(2, '0'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('chapter-title'),
                controller: chapterTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: notebookInk,
                ),
                maxLength: 120,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  counterText: '',
                  hintText: '章节名称',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: rename,
                onTapOutside: (_) {
                  FocusScope.of(context).unfocus();
                  rename(chapterTitle.text);
                },
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              Text(
                '${widget.title} · 第 ${notebookChapters(widget.store, widget.book).indexOf(currentChapter) + 1} 章',
                style: const TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索页面名称',
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
                      Text(
                        query.isEmpty ? '这一章还没有页面，点击右上角 + 开始记录。' : '没有匹配的页面',
                      ),
                      TextButton(onPressed: create, child: const Text('新建页面')),
                    ],
                  ),
                ),
              NotebookReorderList(
                onColor: (indices) => chooseItemColor(
                  context,
                  widget.store,
                  indices.map((i) => entries[i].key),
                ),
                onReorder: (a, b) => reorderItems(
                  widget.store,
                  'pages:${widget.book}',
                  order,
                  a,
                  b,
                ),
                children: [
                  for (final e in entries)
                    SwipeDelete(
                      key: ValueKey(e.key),
                      onUpload: () =>
                          uploadEntries(context, widget.store, [e.key]),
                      onDelete: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除这个页面？'),
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
                      child: NotebookCard(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 14,
                          ),
                          leading: NotebookCover(
                            kind: NoteIconKind.page,
                            index: itemColor(
                              widget.store,
                              e.key,
                              parent: 'chapter:${widget.book}:$currentChapter',
                            ),
                            state: entryIconState(widget.store, e.key),
                            contentIcon: pageContentIcon(e.value),
                          ),
                          title: Text(
                            e.value['title'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: notebookInk,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              widget.store.settings.containsKey(
                                    'publication:${e.key}',
                                  )
                                  ? '${updated(e.key)} · 有已发布版本'
                                  : '${updated(e.key)} · 仅我可见',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                          ),
                          onTap: () => Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  InkPage(store: widget.store, id: e.key),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
