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
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        if (widget.embedded)
          const Text(
            '探索笔记本',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xffe5f0ff), Color(0xfff6f9ff)],
            ),
            border: Border.all(color: const Color(0xffdceaff)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '来自同学们的学习现场',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xff2878f0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '发现新的解题思路',
                      style: TextStyle(
                        fontSize: 20,
                        color: Color(0xff172952),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '从一份真实整理开始，找到适合自己的理解方式。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Color(0xff526888),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.auto_stories_rounded,
                size: 38,
                color: Color(0xff2878f0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: search,
          enabled: !busy,
          maxLength: 100,
          onSubmitted: (_) => reload(),
          decoration: InputDecoration(
            counterText: '',
            hintText: '搜索错题本、笔记本、课程…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: busy ? null : () => reload(),
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '按课程快速查找',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xff71829d),
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: ['全部', '高数', '线代', '概率论', '数据结构', '计网', '计组', '操作系统', '英语']
              .map(
                (s) => ChoiceChip(
                  label: Text(s),
                  selected: search.text.trim() == (s == '全部' ? '' : s),
                  onSelected: busy
                      ? null
                      : (_) {
                          search.text = s == '全部' ? '' : s;
                          reload();
                        },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 17),
        const Text(
          '内容类型',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xff71829d),
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          children: {'all': '全部', 'question': '错题本', 'knowledge': '知识点本'}
              .entries
              .map(
                (e) => ChoiceChip(
                  label: Text(e.value),
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
        const SizedBox(height: 8),
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
              avatar: Icon(
                savedOnly
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 17,
              ),
              label: const Text('我的收藏'),
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
        const SizedBox(height: 9),
        if (busy) const LinearProgressIndicator(minHeight: 3),
        if (error.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(error)),
                  TextButton(
                    onPressed: () => reload(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        if (!busy && items.isEmpty && error.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 35),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xffe5edf8)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 36,
                  color: Color(0xff94baf1),
                ),
                SizedBox(height: 12),
                Text(
                  '暂时没有找到公开笔记本',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 5),
                Text(
                  '换个关键词或筛选条件，再找找看。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xff71829d)),
                ),
              ],
            ),
          ),
        ...items.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xffe5edf8)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                          SubjectArt(
                            (b['subjects'] as String).split(',').first,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
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
                  ),
                  const Divider(height: 20, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                    child: Row(
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
                  ),
                ],
              ),
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
