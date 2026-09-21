import 'package:flutter/material.dart';
import 'brand.dart';
import 'community.dart';
import 'collaboration_pages.dart';
import 'domain.dart';
import 'store.dart';
import 'improvements_page.dart';
import 'learning_profile_page.dart';
import 'notebooks.dart';
import 'ink_page.dart';

String chapterOf(Json entry) {
  final chapter = entry['package']['question']['chapter'] as String? ?? '';
  return chapter.trim().isEmpty ? '未分章' : chapter;
}

class PublicNotebookPage extends StatefulWidget {
  final StudyStore store;
  final CommunityClient client;
  final Json book;
  const PublicNotebookPage({
    super.key,
    required this.store,
    required this.client,
    required this.book,
  });
  @override
  State<PublicNotebookPage> createState() => _PublicNotebookPageState();
}

class _PublicNotebookPageState extends State<PublicNotebookPage> {
  Json? workspace;
  List<Json> entries = [];
  String error = '';
  bool busy = false;
  int tab = 0;
  final forkLocalId = 'book-${newId()}';
  Future<void> forkNotebook() => run(() async {
    final snapshot = await widget.client.request('POST', '$path/fork', {
      'localId': forkLocalId,
    });
    await widget.store.createFork(forkLocalId, snapshot);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存为私有学习本，保留原作来源。加入自己的理解后才计入派生成就。')),
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NotebooksPage(
          store: widget.store,
          initialBook: forkLocalId,
          knowledge: isKnowledgeBook(widget.store, forkLocalId),
          openLesson: (lesson) async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => InkPage(store: widget.store, id: lesson.id),
              ),
            );
          },
        ),
      ),
    );
  });
  String get path => '/v1/notebooks/${widget.book['id']}';
  @override
  void initState() {
    super.initState();
    run(load);
  }

  Future<void> load() async {
    final detail = await widget.client.request('GET', '$path/workspace');
    final result = await widget.client.request('GET', path);
    if (mounted) {
      setState(() {
        workspace = detail;
        entries = (result['items'] as List).cast<Json>();
      });
    }
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '暂时无法完成，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit({bool apply = false}) async {
    final input = TextEditingController(
      text: apply ? '' : workspace?['description'] as String? ?? '',
    );
    final baseline = workspace?['version'];
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(apply ? '申请参与维护' : '编辑学习本简介'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (apply) const Text('通过后可以一起维护简介、查看修改历史，并进入协作聊天。'),
              TextField(
                controller: input,
                minLines: 3,
                maxLines: 8,
                maxLength: apply ? 1000 : 8000,
                decoration: InputDecoration(
                  hintText: apply ? '你希望为这本学习本补充什么？' : '介绍本子的学习目标、整理方式与适用对象…',
                ),
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
            onPressed: () => Navigator.pop(ctx, input.text),
            child: Text(apply ? '提交申请' : '保存修改'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), input.dispose);
    if (value == null || !mounted) return;
    await run(() async {
      await widget.client.request(
        apply ? 'POST' : 'PUT',
        '$path/${apply ? 'apply' : 'description'}',
        apply ? {'reason': value} : {'description': value, 'version': baseline},
      );
      await load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习本'),
        actions: [
          IconButton(
            tooltip: '刷新学习本',
            onPressed: busy ? null : () => run(load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(
              builder: (context, c) => BrandCrop(
                sheet: 'ui-reference',
                sourceWidth: 1491,
                sourceHeight: 1055,
                region: const Rect.fromLTWH(761, 293, 211, 74),
                width: c.maxWidth,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.book['title'] as String,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Color(0xff172952),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              BlueAvatar(
                photo: w?['avatarImage'] as String?,
                index:
                    w?['avatar'] as int? ?? widget.book['avatar'] as int? ?? 0,
                width: 35,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: TextButton(
                  onPressed: w?['ownerId'] == null
                      ? null
                      : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LearningProfilePage(
                              client: widget.client,
                              userId: w!['ownerId'] as String,
                            ),
                          ),
                        ),
                  child: Text(
                    (w?['name'] ?? widget.book['name']) as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length} 条内容',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (w?['description'] as String? ?? '').isEmpty
                ? '记录学习中的问题与理解，与伙伴一起完善。'
                : w!['description'] as String,
            style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(widget.book['subjects'] as String? ?? '学习整理')),
              Chip(
                label: Text(widget.book['kind'] == 'knowledge' ? '知识本' : '错题本'),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.client.request('PUT', '$path/reaction', {
                          'field': 'saved',
                          'value': widget.book['saved'] != 1,
                        });
                        if (mounted) {
                          setState(
                            () => widget.book['saved'] =
                                widget.book['saved'] == 1 ? 0 : 1,
                          );
                        }
                      }),
                icon: Icon(
                  widget.book['saved'] == 1 ? Icons.star : Icons.star_border,
                  color: const Color(0xffedaf2c),
                ),
                label: Text(widget.book['saved'] == 1 ? '已收藏' : '收藏学习本'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.client.request('PUT', '$path/reaction', {
                          'field': 'liked',
                          'value': widget.book['liked'] != 1,
                        });
                        if (mounted) {
                          setState(
                            () => widget.book['liked'] =
                                widget.book['liked'] == 1 ? 0 : 1,
                          );
                        }
                      }),
                icon: Icon(
                  widget.book['liked'] == 1
                      ? Icons.thumb_up
                      : Icons.thumb_up_outlined,
                ),
                label: const Text('点赞'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty)
            Text(error, style: const TextStyle(color: Colors.red)),
          if (w != null) ...[
            if (w['owner'] != true)
              OutlinedButton.icon(
                onPressed: busy ? null : forkNotebook,
                icon: const Icon(Icons.fork_right),
                label: const Text('基于此创建我的版本'),
              ),
            if (w['member'] == true)
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : edit,
                    child: const Text('编辑简介'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookChatPage(
                          client: widget.client,
                          book: widget.book['id'] as String,
                          title: widget.book['title'] as String,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('协作聊天'),
                  ),
                ],
              )
            else
              FilledButton(
                onPressed: busy || w['application'] != ''
                    ? null
                    : () => edit(apply: true),
                child: Text(
                  w['application'] == ''
                      ? '申请参与维护'
                      : applicationLabels[w['application']] ?? '已提交申请',
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ImprovementsPage(
                            client: widget.client,
                            bookId: widget.book['id'] as String,
                          ),
                        ),
                      );
                      if (mounted) run(load);
                    },
              icon: const Icon(Icons.edit_note),
              label: const Text('提交改进 / 贡献记录'),
            ),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('内容')),
                ButtonSegment(value: 1, label: Text('维护者')),
                ButtonSegment(value: 2, label: Text('版本')),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
            const SizedBox(height: 18),
            if (tab == 0) ...[
              const Text(
                '目录',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('这里的内容暂时已撤回。'),
                ),
              for (final chapter in entries.map(chapterOf).toSet())
                ListTile(
                  title: Text(chapter),
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: Color(0xff2878f0),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(chapter)),
                        body: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            ...entries
                                .where((entry) => chapterOf(entry) == chapter)
                                .map((entry) {
                                  final q =
                                      entry['package']['question'] as Json;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.article_outlined,
                                      color: Color(0xff2878f0),
                                    ),
                                    title: Text(q['title'] as String),
                                    subtitle: Text(
                                      '第 ${q['questionNumber']} 条 · ${q['contentKind'] == 'knowledge' ? '知识点' : '例题'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SharedQuestionPage(
                                          store: widget.store,
                                          client: widget.client,
                                          initial: entry,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const Text(
                '讨论附在每条内容下，点击条目查看与交流。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
            if (tab == 1)
              ...(w['members'] as List).map(
                (m) => ListTile(
                  leading: BlueAvatar(
                    photo: m['avatarImage'] as String?,
                    index: m['avatar'] as int? ?? 0,
                    width: 34,
                  ),
                  title: Text(m['name'] as String),
                  subtitle: const Text('共同维护者'),
                ),
              ),
            if (tab == 2) ...[
              if ((w['history'] as List).isEmpty) const Text('还没有简介修改记录。'),
              ...(w['history'] as List).map(
                (h) => ExpansionTile(
                  title: Text('v${h['version']} · ${h['name']} 更新简介'),
                  subtitle: Text(
                    DateTime.fromMicrosecondsSinceEpoch(
                      (h['created'] as int) ~/ 1000,
                    ).toLocal().toString().substring(0, 16),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(h['description'] as String),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
