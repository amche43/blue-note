import 'package:flutter/material.dart';
import 'community.dart';
import 'domain.dart';
import 'store.dart';
import 'brand.dart';
import 'public_notebook.dart';

class HallPage extends StatefulWidget {
  final CommunityClient client;
  final StudyStore store;
  final bool embedded, initialSaved;
  const HallPage({
    super.key,
    required this.client,
    required this.store,
    this.embedded = false,
    this.initialSaved = false,
  });
  @override
  State<HallPage> createState() => _HallPageState();
}

class _HallPageState extends State<HallPage> {
  final search = TextEditingController();
  List<Json> items = [];
  String sort = 'newest', kind = 'all', error = '';
  bool busy = false;
  bool savedOnly = false;
  int? next;
  @override
  void initState() {
    super.initState();
    savedOnly = widget.initialSaved;
    reload();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> reload({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      if (!more) {
        items = [];
        next = null;
      }
    });
    try {
      final uri = Uri(
        path: '/v1/hall',
        queryParameters: {
          'q': search.text.trim(),
          'sort': sort,
          'kind': kind,
          'saved': savedOnly ? '1' : '0',
          'offset': '${more ? next ?? 0 : 0}',
        },
      );
      final result = await widget.client.request('GET', uri.toString());
      if (mounted) {
        setState(() {
          items = [
            if (more) ...items,
            ...(result['items'] as List).cast<Json>(),
          ];
          next = result['nextOffset'] as int?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '大厅加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> react(Json book, String field) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.client.request(
        'PUT',
        '/v1/notebooks/${book['id']}/reaction',
        {'field': field, 'value': book[field] != 1},
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '操作未确认完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error.isEmpty) await reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : AppBar(title: const Text('探索笔记本')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.embedded)
          const Text(
            '探索笔记本',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
        const Text(
          '发现同学们正在建设的知识。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          enabled: !busy,
          maxLength: 100,
          onSubmitted: (_) => reload(),
          decoration: InputDecoration(
            counterText: '',
            hintText: '搜索错题本、笔记本、课程…',
            suffixIcon: IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: busy ? null : () => reload(),
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: ['全部', '高数', '线代', '概率论', '数据结构', '计网', '计组', '操作系统', '英语']
              .map(
                (s) => ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                  backgroundColor: const Color(0xffeef4fe),
                  label: Text(s, style: const TextStyle(fontSize: 10)),
                  onPressed: busy
                      ? null
                      : () {
                          search.text = s == '全部' ? '' : s;
                          reload();
                        },
                ),
              )
              .toList(),
        ),
        Wrap(
          spacing: 8,
          children: {'all': '全部', 'question': '错题本', 'knowledge': '知识点本'}
              .entries
              .map(
                (e) => ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(e.value, style: const TextStyle(fontSize: 11)),
                  selected: kind == e.key,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() => kind = e.key);
                          reload();
                        },
                ),
              )
              .toList(),
        ),
        Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: sort,
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: Colors.blueGrey,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('最近更新')),
                    DropdownMenuItem(value: 'likes', child: Text('点赞最多')),
                    DropdownMenuItem(value: 'saves', child: Text('收藏最多')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => sort = v!);
                          reload();
                        },
                ),
              ),
            ),
            FilterChip(
              visualDensity: VisualDensity.compact,
              label: const Text('我的收藏', style: TextStyle(fontSize: 11)),
              selected: savedOnly,
              onSelected: busy
                  ? null
                  : (v) {
                      setState(() => savedOnly = v);
                      reload();
                    },
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!busy && items.isEmpty && error.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('暂无匹配的公开本子。可以换个关键词，或发布自己的整理。'),
          ),
        ...items.map(
          (b) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffe5edf9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: busy
                      ? null
                      : () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicNotebookPage(
                                store: widget.store,
                                client: widget.client,
                                book: Map<String, dynamic>.from(b),
                              ),
                            ),
                          );
                          if (mounted) await reload();
                        },
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b['title'] as String,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xff172952),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${b['name']} · ${b['count']}条公开内容',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SubjectArt((b['subjects'] as String).split(',').first),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children:
                      [
                            b['subjects'] as String,
                            b['kind'] == 'knowledge' ? '知识点本' : '错题本',
                          ]
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffedf4ff),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xff2878f0),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(50, 32),
                      ),
                      onPressed: busy ? null : () => react(b, 'saved'),
                      icon: Icon(
                        b['saved'] == 1 ? Icons.star : Icons.star_border,
                        size: 17,
                        color: const Color(0xfff4b534),
                      ),
                      label: Text(
                        '收藏 ${b['saves']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(50, 32),
                      ),
                      onPressed: busy ? null : () => react(b, 'liked'),
                      icon: Icon(
                        b['liked'] == 1
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        size: 16,
                      ),
                      label: Text(
                        '点赞 ${b['likes']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PublicNotebookPage(
                                    store: widget.store,
                                    client: widget.client,
                                    book: Map<String, dynamic>.from(b),
                                  ),
                                ),
                              );
                              if (mounted) await reload();
                            },
                      child: const Text(
                        '打开本子 ›',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (next != null)
          TextButton(
            onPressed: busy ? null : () => reload(more: true),
            child: const Text('加载更多'),
          ),
      ],
    ),
  );
}
