import 'dart:convert';
import 'package:flutter/material.dart';
import 'brand.dart';
import 'community.dart';
import 'collaboration_pages.dart';
import 'account_page.dart';
import 'avatar_page.dart';
import 'contribution_calendar.dart';
import 'domain.dart';
import 'hall.dart';
import 'notebooks.dart';
import 'store.dart';
import 'create_page.dart';
import 'learning_profile_page.dart';

const studioBlue = Color(0xff2878f0);

class StudioShell extends StatefulWidget {
  final StudyStore store;
  final Future<void> Function(Lesson) open;
  final VoidCallback record, library, settings, practice;
  const StudioShell({
    super.key,
    required this.store,
    required this.open,
    required this.record,
    required this.library,
    required this.settings,
    required this.practice,
  });
  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int tab = 0;
  bool exploreSaved = false;
  StudyStore get store => widget.store;
  void books([bool? knowledge, String? id]) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => knowledge == null
          ? AllNotebooksPage(store: store, openLesson: widget.open)
          : NotebooksPage(
              store: store,
              knowledge: knowledge,
              initialBook: id,
              openLesson: widget.open,
            ),
    ),
  );
  Future<void> addBook() async {
    final name = TextEditingController();
    String kind = 'question';
    String error = '';
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.viewInsetsOf(ctx).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '创建学习本',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const Text('先为自己的学习留一个位置。'),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 80,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '学习本名称',
                    hintText: '例如：高数极限错题本',
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'question', label: Text('错题本')),
                    ButtonSegment(value: 'knowledge', label: Text('知识本')),
                  ],
                  selected: {kind},
                  onSelectionChanged: saving
                      ? null
                      : (v) => update(() => kind = v.first),
                ),
                const SizedBox(height: 16),
                const Text(
                  '仅自己可见。内容整理好后再选择分享。',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                if (error.isNotEmpty) Text(error),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (name.text.trim().isEmpty) {
                            update(() => error = '请给学习本取个名字');
                            return;
                          }
                          update(() => saving = true);
                          try {
                            final id = 'book-${newId()}';
                            await store.setting(
                              'notebook:$id',
                              jsonEncode({
                                'title': name.text.trim(),
                                'kind': kind,
                              }),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              setState(() {});
                              books(kind == 'knowledge', id);
                            }
                          } catch (_) {
                            if (ctx.mounted) {
                              update(() {
                                saving = false;
                                error = '未保存，请重试';
                              });
                            }
                          }
                        },
                  child: Text(saving ? '正在创建…' : '创建并打开'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), name.dispose);
  }

  bool refreshingProfile = false;
  Future<void> refreshAccountAvatar() async {
    final raw = store.settings['community'];
    if (raw == null || refreshingProfile) return;
    refreshingProfile = true;
    try {
      final me = await CommunityClient(
        CommunityClient.parse(raw),
      ).request('GET', '/v1/me');
      if (!mounted || store.settings['community'] != raw) return;
      final image = me['avatarImage'] as String? ?? '';
      if (store.settings['avatarImage'] != image) {
        await store.setting('avatarImage', image);
      }
    } catch (_) {
      /* Keep the last confirmed avatar; the avatar page provides explicit refresh errors. */
    } finally {
      refreshingProfile = false;
    }
  }

  Future<void> editProfile() async {
    final name = TextEditingController(
      text: store.settings['profileName'] ?? '同学',
    );
    final bio = TextEditingController(
      text: store.settings['profileBio'] ?? '以自己的方式，记录学习与成长。',
    );
    int avatar = int.tryParse(store.settings['avatar'] ?? '0') ?? 0;
    String error = '';
    bool busy = false, avatarChanged = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('编辑我的资料'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: '昵称'),
                ),
                TextField(
                  controller: bio,
                  maxLength: 100,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '学习介绍'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(
                    8,
                    (i) => InkWell(
                      onTap: busy
                          ? null
                          : () => update(() {
                              avatar = i;
                              avatarChanged = true;
                            }),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: avatar == i
                                ? studioBlue
                                : Colors.transparent,
                            width: 2,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: BlueAvatar(index: i, width: 36),
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AvatarPage(store: store),
                            ),
                          );
                          if (ctx.mounted) {
                            update(() {
                              avatar =
                                  int.tryParse(
                                    store.settings['avatar'] ?? '0',
                                  ) ??
                                  0;
                              avatarChanged = false;
                            });
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('自定义头像'),
                ),
                const Text(
                  '已连接时昵称、头像同步到账号，学习介绍保存在此设备。',
                  style: TextStyle(fontSize: 11),
                ),
                if (error.isNotEmpty) Text(error),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      try {
                        final raw = store.settings['community'];
                        if (raw != null) {
                          await CommunityClient(
                            CommunityClient.parse(raw),
                          ).request('PUT', '/v1/me', {
                            'name': name.text.trim().isEmpty
                                ? '同学'
                                : name.text.trim(),
                            'avatar': avatar,
                            'useDefault': avatarChanged,
                          });
                        }
                        await store.setting(
                          'profileName',
                          name.text.trim().isEmpty ? '同学' : name.text.trim(),
                        );
                        await store.setting('profileBio', bio.text.trim());
                        await store.setting('avatar', '$avatar');
                        if (avatarChanged) {
                          await store.setting('avatarImage', '');
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      } catch (_) {
                        if (ctx.mounted) {
                          update(() {
                            busy = false;
                            error = '资料未保存，请重试';
                          });
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      name.dispose();
      bio.dispose();
    });
  }

  Widget section(String title, {VoidCallback? more}) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (more != null)
          InkWell(
            onTap: more,
            child: const Text(
              '查看全部 ›',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
      ],
    ),
  );
  Widget search(VoidCallback action) => InkWell(
    onTap: action,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe7eef9)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, size: 18, color: Colors.blueGrey),
          SizedBox(width: 8),
          Text(
            '搜索学习本、知识点、题目…',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  );
  Widget stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xff172952),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
        ),
      ],
    ),
  );
  List<Widget> home() {
    final ordered = [...store.events]..sort(compareEvents);
    final recent =
        store.lessons
            .where((l) => l.id == store.settings['lastOpenedLesson'])
            .firstOrNull ??
        ordered.reversed
            .map(
              (e) => store.lessons.where((l) => l.id == e.lessonId).firstOrNull,
            )
            .whereType<Lesson>()
            .firstOrNull;
    final next = recent ?? store.due.firstOrNull ?? store.lessons.first;
    final today = dayKey(DateTime.now());
    final daily = contributions(store.events)[today] ?? [];
    final allBooks = notebooks(store);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '你好，${store.settings['profileName'] ?? '同学'}\n今天也继续加油吧！',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          IconButton(
            tooltip: '查看通知',
            onPressed: () => setState(() => tab = 3),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      const SizedBox(height: 14),
      search(widget.library),
      section('继续学习'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xffeff6ff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SubjectArt(next.subject),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    next.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    recent == null ? '从一条例题开始' : '上次学习 · ${next.subject}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(76, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => widget.open(next),
                child: const Text('继续学习 ›', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ),
      ),
      section('我的学习本', more: () => books()),
      SizedBox(
        height: 88,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            ...allBooks.entries.map((b) {
              final count = store.questions.values
                  .where(
                    (q) => q['notebookId'] == b.key && q['deleted'] == false,
                  )
                  .length;
              return InkWell(
                onTap: () => books(isKnowledgeBook(store, b.key), b.key),
                child: Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isKnowledgeBook(store, b.key)
                          ? [const Color(0xffe8f9f5), const Color(0xffd9f1fb)]
                          : [const Color(0xffecf3ff), const Color(0xffe2eaff)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$count 条内容',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            InkWell(
              onTap: addBook,
              child: Container(
                width: 70,
                decoration: BoxDecoration(
                  color: const Color(0xffedf4ff),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: studioBlue),
                    Text(
                      '新建',
                      style: TextStyle(fontSize: 12, color: studioBlue),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      section('今日学习'),
      Row(
        children: [
          stat('${daily.where((e) => e.type == 'question').length}', '整理记录'),
          stat('${daily.where((e) => e.type == 'attempt').length}', '完成复习'),
          stat('${daily.where((e) => e.type == 'note').length}', '写下笔记'),
        ],
      ),
      const SizedBox(height: 24),
      ContributionCalendar(store: store),
      section('快捷创建'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: addBook,
              icon: const Icon(Icons.library_add_outlined, size: 16),
              label: const Text('建学习本', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.record,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('记录内容', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: widget.practice,
              child: const Text('复习中心', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
      section('最近更新', more: widget.library),
      if (ordered.isEmpty)
        const Text(
          '记录第一条内容后，更新会出现在这里。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
      ...ordered.reversed.take(3).map((e) {
        final lesson = store.lessons
            .where((l) => l.id == e.lessonId)
            .firstOrNull;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.auto_stories_outlined,
            color: studioBlue,
            size: 20,
          ),
          title: Text(
            lesson?.title ?? '已移除的条目',
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            '${dayKey(DateTime.fromMillisecondsSinceEpoch(e.at))} · ${e.type == 'question'
                ? '整理内容'
                : e.type == 'note'
                ? '更新笔记'
                : '完成复习'}',
            style: const TextStyle(fontSize: 10),
          ),
          onTap: lesson == null ? null : () => widget.open(lesson),
        );
      }),
      TextButton(onPressed: widget.library, child: const Text('学习')),
    ];
  }

  List<Widget> profile() {
    final entries = store.questions.values
        .where((q) => q['deleted'] == false)
        .toList();
    return [
      LayoutBuilder(
        builder: (_, c) => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BrandCrop(
                  sheet: 'ui-reference',
                  region: const Rect.fromLTWH(761, 293, 211, 74),
                  sourceWidth: 1491,
                  sourceHeight: 1055,
                  width: c.maxWidth,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: BlueAvatar(
                  photo: store.settings['avatarImage'],
                  index: int.tryParse(store.settings['avatar'] ?? '0') ?? 0,
                  width: 64,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: TextButton(
                onPressed: editProfile,
                child: const Text('编辑资料'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        store.settings['profileName'] ?? '同学',
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
      ),
      Text(
        store.settings['profileBio'] ?? '以自己的方式，记录学习与成长。',
        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
      const Text(
        'Keep Learning. Keep Sharing.',
        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          stat('${notebooks(store).length}', '学习本'),
          stat(
            '${entries.where((q) => q['contentKind'] == 'knowledge').length}',
            '知识卡片',
          ),
          stat(
            '${entries.where((q) => q['contentKind'] != 'knowledge').length}',
            '题目',
          ),
          stat(
            '${store.events.where((e) => e.type == 'attempt').length}',
            '复习记录',
          ),
        ],
      ),
      const SizedBox(height: 24),
      ContributionCalendar(store: store),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.workspace_premium_outlined,
          color: studioBlue,
        ),
        title: const Text('成就与开放学习履历'),
        subtitle: const Text('记录创造、维护与共建成果'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => LearningProfilePage(store: store)),
        ),
      ),
      section('我的学习成果'),
      Wrap(
        spacing: 8,
        children: [
          ActionChip(label: const Text('我创建的'), onPressed: () => books()),
          ActionChip(label: const Text('知识点本'), onPressed: () => books(true)),
          ActionChip(
            label: const Text('我的收藏'),
            onPressed: () => setState(() {
              exploreSaved = true;
              tab = 1;
            }),
          ),
        ],
      ),
      ...notebooks(store).entries.map(
        (b) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.menu_book, color: studioBlue),
          title: Text(b.value, style: const TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => books(isKnowledgeBook(store, b.key), b.key),
        ),
      ),
      section('工具与设置'),
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const Text('账号登录与注册'),
        onTap: connectCommunity,
      ),
      ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('备份、同步与应用设置'),
        onTap: widget.settings,
      ),
    ];
  }

  Widget explore() {
    final raw = store.settings['community'];
    try {
      if (raw != null) {
        return HallPage(
          store: store,
          client: CommunityClient(CommunityClient.parse(raw)),
          embedded: true,
          initialSaved: exploreSaved,
          key: ValueKey(exploreSaved),
        );
      }
    } catch (_) {
      /* Render the connection setup entry below. */
    }
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          '探索学习本',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        search(connectCommunity),
        const SizedBox(height: 32),
        const Center(child: BlueMascot(width: 110)),
        const SizedBox(height: 20),
        const Text('连接后台，发现大家的学习成果', textAlign: TextAlign.center),
        const Text(
          '公开的错题本、知识本会出现在这里。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: connectCommunity, child: const Text('连接本机社区')),
      ],
    );
  }

  Future<void> connectCommunity() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(store: store)),
    );
    if (mounted) setState(() {});
  }

  Widget notifications() {
    try {
      final raw = store.settings['community'];
      if (raw != null) {
        return CollaborationInbox(
          client: CommunityClient(CommunityClient.parse(raw)),
          store: store,
        );
      }
    } catch (_) {}
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          '通知',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 28),
        const Center(child: BlueMascot(width: 100)),
        const SizedBox(height: 20),
        const Text('与伙伴一起建设学习本', textAlign: TextAlign.center),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '在这里处理共同维护申请，与学习本的伙伴聊天。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
        ),
        FilledButton(onPressed: connectCommunity, child: const Text('连接本机社区')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff8fbff),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: tab == 1
              ? explore()
              : tab == 3
              ? notifications()
              : tab == 2
              ? CreatePage(
                  store: store,
                  createBook: addBook,
                  openLesson: widget.open,
                )
              : ListView(
                  key: ValueKey('studio-$tab'),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: tab == 0 ? home() : profile(),
                ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xffe8eef8))),
        ),
        height: 64,
        child: Row(
          children: List.generate(5, (i) {
            if (i == 2) {
              return Expanded(
                child: Center(
                  child: IconButton.filled(
                    tooltip: '添加',
                    onPressed: () => setState(() => tab = 2),
                    icon: const Icon(Icons.add, size: 28),
                  ),
                ),
              );
            }
            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    tab = i;
                    exploreSaved = false;
                  });
                  if (i == 4) refreshAccountAvatar();
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      [
                        Icons.home_outlined,
                        Icons.explore_outlined,
                        Icons.add,
                        Icons.notifications_none,
                        Icons.person_outline,
                      ][i],
                      color: tab == i ? studioBlue : Colors.blueGrey,
                      size: 22,
                    ),
                    Text(
                      ['首页', '探索', '', '通知', '我的'][i],
                      style: TextStyle(
                        fontSize: 10,
                        color: tab == i ? studioBlue : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );
}

class WelcomePage extends StatefulWidget {
  final StudyStore store;
  final Widget child;
  const WelcomePage({super.key, required this.store, required this.child});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool entered = false, busy = false;
  String error = '';
  @override
  Widget build(BuildContext context) =>
      entered || widget.store.settings['welcomeSeen'] == 'true'
      ? widget.child
      : Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xffe6f3ff), Colors.white, Color(0xffdceeff)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Text(
                        '好的学习\n从分享开始',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.8,
                          color: Color(0xff185bcc),
                        ),
                      ),
                      const SizedBox(height: 30),
                      const BlueMascot(width: 200),
                      const SizedBox(height: 22),
                      const Text(
                        'Blue-note 蓝笔',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: studioBlue,
                        ),
                      ),
                      const Text(
                        '开源你的学习过程。\nOpen Your Learning.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (error.isNotEmpty) Text(error),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() => busy = true);
                                try {
                                  await widget.store.setting(
                                    'welcomeSeen',
                                    'true',
                                  );
                                  if (mounted) setState(() => entered = true);
                                } catch (_) {
                                  if (mounted) {
                                    setState(() {
                                      busy = false;
                                      error = '暂未保存，请重试';
                                    });
                                  }
                                }
                              },
                        child: const Text('开始我的学习'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
}
