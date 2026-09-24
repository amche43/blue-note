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
      Row(
        children: [
          Expanded(
            child: Text(
              '你好，${store.settings['profileName'] ?? '同学'}\n${greetingFor(DateTime.now())}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          NotebookAddButton(onPressed: addBook, tooltip: '新建笔记本'),
        ],
      ),
      const SizedBox(height: 14),
      section('我的学习本', more: () => books()),
      if (notebooks(store).isEmpty)
        ListTile(
          leading: const Icon(Icons.auto_stories_outlined, color: studioBlue),
          title: const Text('为知识留一个位置'),
          subtitle: const Text('进入我的学习本，开始第一本笔记'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => books(),
        ),
      NotebookReorderList(
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
                  leading: NotebookCover(state: bookIconState(store, b.key)),
                  title: Text(b.value),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => books(false, b.key),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      ContributionCalendar(store: store),
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
        const Center(child: SceneMascot(MascotScene.explore, width: 180)),
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
        const Center(child: SceneMascot(MascotScene.messages, width: 180)),
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
          children: List.generate(4, (position) {
            final i = [0, 1, 3, 4][position];
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
