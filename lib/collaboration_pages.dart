import 'dart:async';
import 'package:flutter/material.dart';
import 'brand.dart';
import 'community.dart';
import 'domain.dart';
import 'store.dart';
import 'improvements_page.dart';

const applicationLabels = {
  'pending': '待处理',
  'accepted': '已同意',
  'rejected': '未通过',
};

class CollaborationInbox extends StatefulWidget {
  final CommunityClient client;
  final StudyStore store;
  const CollaborationInbox({
    super.key,
    required this.client,
    required this.store,
  });
  @override
  State<CollaborationInbox> createState() => _CollaborationInboxState();
}

class _CollaborationInboxState extends State<CollaborationInbox> {
  List<Json> applications = [], rooms = [], improvements = [];
  String error = '';
  bool busy = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final result = await widget.client.request('GET', '/v1/inbox');
      if (mounted) {
        setState(() {
          applications = (result['applications'] as List).cast<Json>();
          rooms = (result['rooms'] as List).cast<Json>();
          improvements = (result['improvements'] as List? ?? []).cast<Json>();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '通知暂时无法加载，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(Json a, String status) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.client.request(
        'PUT',
        '/v1/notebooks/${a['book']}/applications',
        {'id': a['id'], 'status': status},
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '处理结果未确认，请刷新',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error.isEmpty) await load();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '通知',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: '刷新通知',
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          '一起维护，让每一份理解更完整。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 20),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('协作申请')),
            ButtonSegment(value: 1, label: Text('聊天')),
            ButtonSegment(value: 2, label: Text('改进')),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Text(error, style: const TextStyle(color: Colors.red)),
        if (tab == 2) ...[
          if (!busy && improvements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  BlueMascot(width: 90),
                  SizedBox(height: 16),
                  Text('还没有改进消息'),
                  Text(
                    '收到的提案与自己提交的处理结果会出现在这里。',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          ...improvements.map(
            (item) => ListTile(
              leading: Icon(
                item['status'] == 'pending'
                    ? Icons.rate_review_outlined
                    : Icons.task_alt,
                color: const Color(0xff2878f0),
              ),
              title: Text(
                item['entryTitle'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${item['title']}\n${item['canReview'] == 1 ? '收到 ${item['name']} 的改进' : '我提交的改进'} · ${{'pending': '待核对', 'accepted': '已合并', 'rejected': '未采纳'}[item['status']]}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImprovementsPage(
                      client: widget.client,
                      bookId: item['book'] as String,
                      initialProposalId: item['id'] as String,
                    ),
                  ),
                );
                if (mounted) await load();
              },
            ),
          ),
        ],
        if (tab == 0) ...[
          if (!busy && applications.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  BlueMascot(width: 90),
                  SizedBox(height: 16),
                  Text('还没有协作申请'),
                  Text(
                    '在学习本中申请参与维护，处理结果会出现在这里。',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          ...applications.map(
            (a) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BlueAvatar(
                        photo: a['avatarImage'] as String?,
                        index: a['avatar'] as int? ?? 0,
                        width: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          a['canReview'] == 1
                              ? '${a['name']} 申请参与维护'
                              : '我的维护申请',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('《${a['title']}》'),
                  Text(
                    a['reason'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.blueGrey,
                    ),
                  ),
                  if (a['canReview'] == 1 && a['status'] == 'pending')
                    Row(
                      children: [
                        TextButton(
                          onPressed: busy ? null : () => review(a, 'rejected'),
                          child: const Text('拒绝'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: busy ? null : () => review(a, 'accepted'),
                          child: const Text('同意共同维护'),
                        ),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        applicationLabels[a['status']] ?? '未知状态',
                        style: const TextStyle(color: Color(0xff2878f0)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ] else if (tab == 1) ...[
          if (!busy && rooms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Text('加入共同维护后，在这里与学习本的伙伴交流。'),
            ),
          ...rooms.map(
            (r) => ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: const BlueAvatar(index: 1),
              title: Text(r['title'] as String),
              subtitle: const Text('学习本协作聊天'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => BookChatPage(
                    client: widget.client,
                    book: r['id'] as String,
                    title: r['title'] as String,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CommunityPage(store: widget.store, feedbackOnly: true),
            ),
          ),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('纠错反馈与处理结果'),
        ),
      ],
    ),
  );
}

class BookChatPage extends StatefulWidget {
  final CommunityClient client;
  final String book, title;
  const BookChatPage({
    super.key,
    required this.client,
    required this.book,
    required this.title,
  });
  @override
  State<BookChatPage> createState() => _BookChatPageState();
}

class _BookChatPageState extends State<BookChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Json> messages = [];
  String error = '', rid = newId();
  String? pending, draftSticker;
  bool sending = false, loading = false;
  Timer? timer;
  String get path => '/v1/notebooks/${widget.book}/messages';
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (ModalRoute.of(context)?.isCurrent == true) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    loading = true;
    try {
      final data = await widget.client.request('GET', path);
      if (mounted) {
        final next = (data['items'] as List).cast<Json>();
        final changed =
            messages.isEmpty ||
            next.isNotEmpty && next.last['id'] != messages.last['id'];
        setState(() {
          messages = next;
          error = '';
        });
        if (changed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '消息刷新失败，稍后重试',
        );
      }
    } finally {
      loading = false;
    }
  }

  Future<void> send() async {
    if (sending || (input.text.trim().isEmpty && draftSticker == null)) return;
    // Keep the same payload and id when delivery is uncertain.
    pending ??= [
      if (input.text.trim().isNotEmpty) input.text.trim(),
      ?draftSticker,
    ].join('\n');
    setState(() => sending = true);
    try {
      await widget.client.request('POST', path, {
        'requestId': rid,
        'body': pending,
      });
      if (mounted) {
        input.clear();
        pending = null;
        draftSticker = null;
        rid = newId();
        await load();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '消息尚未确认送达，点击重试发送',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: '刷新消息',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '共同维护者聊天 · 显示最近200条',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (messages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('从一道题、一处疑问开始交流。', textAlign: TextAlign.center),
                  ),
                ...messages.map(
                  (m) => Align(
                    alignment: m['mine'] == 1
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 290),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: m['mine'] == 1
                            ? const Color(0xffe3efff)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              BlueAvatar(
                                photo: m['avatarImage'] as String?,
                                index: m['avatar'] as int? ?? 0,
                                width: 24,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${m['name']} · ${DateTime.fromMicrosecondsSinceEpoch((m['created'] as int) ~/ 1000).toLocal().toString().substring(5, 16)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          BlueMessageBody(m['body'] as String),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (draftSticker != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  BlueSticker(
                    stickerNames.indexWhere((n) => draftSticker == '[蓝笔表情:$n]'),
                    width: 52,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '表情已选好',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ),
                  IconButton(
                    tooltip: '移除表情',
                    onPressed: sending || pending != null
                        ? null
                        : () => setState(() => draftSticker = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '蓝笔表情',
                  onPressed: sending || pending != null
                      ? null
                      : () async {
                          FocusScope.of(context).unfocus();
                          final sticker = await chooseBlueSticker(context);
                          if (sticker != null && mounted) {
                            setState(() => draftSticker = sticker);
                          }
                        },
                  icon: const Icon(
                    Icons.emoji_emotions_outlined,
                    color: Color(0xff2878f0),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    readOnly: sending || pending != null,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: '聊聊本子的整理思路…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: sending ? null : send,
                  child: Text(
                    sending
                        ? '发送中'
                        : pending != null
                        ? '重试'
                        : '发送',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
