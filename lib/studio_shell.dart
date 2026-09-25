import 'notebook_actions.dart';
import 'dart:convert';
import 'dart:async';
import 'daily_greeting.dart';
import 'swipe_delete.dart';
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
import 'notebook_ui.dart';
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

class _StudioShellState extends State<StudioShell> with WidgetsBindingObserver {
  Timer? midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleGreeting();
    widget.store.addListener(refreshBooks);
  }

  void refreshBooks() {
    if (mounted) setState(() {});
  }

  void scheduleGreeting() {
    midnight?.cancel();
    final now = DateTime.now();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (mounted) {
          setState(() {});
          scheduleGreeting();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      scheduleGreeting();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    widget.store.removeListener(refreshBooks);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
    final names = notebooks(store).values.toSet();
    var n = 1;
    while (names.contains('新建笔记本$n')) {
      n++;
    }
    final id = 'book-${newId()}';
    await store.setting(
      'notebook:$id',
      jsonEncode({'title': '新建笔记本$n', 'kind': 'question'}),
    );
    if (mounted) {
      final name = await requestItemName(context, '新建笔记本$n');
      if (name != null) {
        await store.setting(
          'notebook:$id',
          jsonEncode({'title': name, 'kind': 'question'}),
        );
      }
      if (mounted) books(false, id);
    }
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
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        if (more != null)
          TextButton.icon(
            onPressed: more,
            label: const Text('查看全部'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
          ),
      ],
    ),
  );
  Widget stat(String value, String label, {VoidCallback? onTap}) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
      ),
    ),
  );
  List<Widget> home() {
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe7f1ff), Color(0xfff5f9ff)],
          ),
          border: Border.all(color: const Color(0xffdceaff)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '今天，从这里继续',
                    style: TextStyle(
                      fontSize: 12,
                      color: studioBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '你好，${store.settings['profileName'] ?? '同学'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff172952),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    greetingFor(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xff526888),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NotebookAddButton(onPressed: addBook, tooltip: '新建笔记本'),
          ],
        ),
      ),
      section('我的笔记本'),
      if (notebooks(store).isEmpty)
        ListTile(
          leading: const Icon(Icons.auto_stories_outlined, color: studioBlue),
          title: const Text('为知识留一个位置'),
          subtitle: const Text('点击 + 开始第一本笔记'),
          onTap: addBook,
        ),
      NotebookReorderList(
        onColor: (indices) => chooseItemColor(
          context,
          store,
          indices.map((i) => notebooks(store).keys.elementAt(i)),
        ),
        onReorder: (a, b) =>
            reorderItems(store, 'books', notebooks(store).keys.toList(), a, b),
        children: [
          for (final b in notebooks(store).entries)
            SwipeDelete(
              key: ValueKey(b.key),
              onDelete: () async {
                await confirmDeleteNotebook(context, store, b.key);
                if (mounted) setState(() {});
              },
              onUpload: () => uploadEntries(
                context,
                store,
                store.questions.entries
                    .where((e) => e.value['notebookId'] == b.key)
                    .map((e) => e.key)
                    .toList(),
              ),
              child: NotebookCard(
                child: ListTile(
                  leading: NotebookCover(
                    index: itemColor(store, b.key),
                    state: bookIconState(store, b.key),
                  ),
                  title: Text(b.value),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => books(false, b.key),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffe5edf8)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: ContributionCalendar(store: store),
      ),
    ];
  }

  List<Widget> profile() {
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
      const SizedBox(height: 20),
      ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('设置'),
        subtitle: const Text('账号、数据与应用偏好'),
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
    return _CommunityIntro(
      title: '探索笔记本',
      eyebrow: '发现与分享',
      headline: '看看同学们如何理解一道题',
      description: '连接本机社区后，浏览公开笔记本、收藏有用的整理，也可以分享自己的学习过程。',
      icon: Icons.explore_outlined,
      features: const [
        (Icons.auto_stories_outlined, '发现公开笔记本'),
        (Icons.bookmark_border_rounded, '收藏值得回看的内容'),
      ],
      onConnect: connectCommunity,
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
    return _CommunityIntro(
      title: '通知',
      eyebrow: '一起维护',
      headline: '每一次交流，都让理解更完整',
      description: '连接本机社区后，在这里查看协作申请、改进提案和笔记本聊天。',
      icon: Icons.forum_outlined,
      features: const [
        (Icons.mark_email_unread_outlined, '处理协作与改进'),
        (Icons.chat_bubble_outline_rounded, '与学习伙伴交流'),
      ],
      onConnect: connectCommunity,
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
              : ListView(
                  key: ValueKey('studio-$tab'),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
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
        height: 70,
        child: Row(
          children: List.generate(4, (position) {
            final i = [0, 1, 3, 4][position];
            final selected = tab == i;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
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
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 54,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xffe8f1ff)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        [
                          Icons.home_outlined,
                          Icons.explore_outlined,
                          Icons.add,
                          Icons.notifications_none,
                          Icons.person_outline,
                        ][i],
                        color: selected ? studioBlue : const Color(0xff71829d),
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ['首页', '探索', '', '通知', '我的'][i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? studioBlue : const Color(0xff71829d),
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

class _CommunityIntro extends StatelessWidget {
  final String title, eyebrow, headline, description;
  final IconData icon;
  final List<(IconData, String)> features;
  final VoidCallback onConnect;
  const _CommunityIntro({
    required this.title,
    required this.eyebrow,
    required this.headline,
    required this.description,
    required this.icon,
    required this.features,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe5f0ff), Color(0xfff6f9ff)],
          ),
          border: Border.all(color: const Color(0xffdceaff)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: studioBlue, size: 28),
            ),
            const SizedBox(height: 24),
            Text(
              eyebrow,
              style: const TextStyle(
                color: studioBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              headline,
              style: const TextStyle(
                fontSize: 21,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: Color(0xff172952),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xff526888),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      for (final feature in features)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(feature.$1, size: 20, color: studioBlue),
              const SizedBox(width: 12),
              Text(
                feature.$2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: onConnect,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text('连接本机社区'),
      ),
    ],
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
                      Image.asset('assets/brand/launcher.png', width: 150),
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
