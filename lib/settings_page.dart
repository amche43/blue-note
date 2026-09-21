import 'dart:convert';
import 'package:flutter/material.dart';
import 'account_page.dart';
import 'community.dart';
import 'store.dart';

class AppSettingsPage extends StatelessWidget {
  final StudyStore store;
  final VoidCallback backup, sync;
  const AppSettingsPage({
    super.key,
    required this.store,
    required this.backup,
    required this.sync,
  });
  Future<void> logout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出当前账号？'),
        content: const Text('本机学习本与草稿会保留在此设备。退出后，社区操作需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final config = CommunityClient.parse(store.settings['community']!);
      await CommunityClient(config).request('POST', '/v1/auth/logout', {});
      config.remove('token');
      await store.setting('community', jsonEncode(config));
      await store.setting('avatarImage', '');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('退出未完成，请连接后台后重试')));
      }
    }
  }

  Widget group(String title, List<Widget> items) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: items),
        ),
      ],
    ),
  );
  Widget item(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    leading: Icon(icon, color: const Color(0xff2878f0)),
    title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: action,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      var signedIn = false;
      try {
        CommunityClient.parse(store.settings['community'] ?? '');
        signedIn = true;
      } catch (_) {}
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            group('账号', [
              item(
                Icons.account_circle_outlined,
                signedIn ? '切换账号' : '登录 / 注册',
                signedIn
                    ? '当前：${store.settings['profileName'] ?? '同学'}'
                    : '连接社区，与同学共同建设',
                () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => AccountPage(store: store)),
                ),
              ),
              if (signedIn)
                item(
                  Icons.logout,
                  '退出登录',
                  '保留此设备上的学习内容',
                  () => logout(context),
                ),
            ]),
            group('数据与连接', [
              item(Icons.backup_outlined, '备份与恢复', '导出、导入完整学习成果', backup),
              item(Icons.sync, '跨设备同步', '管理个人同步服务', sync),
            ]),
            group('帮助', [
              item(
                Icons.feedback_outlined,
                '我的纠错反馈',
                '查看反馈进度与处理回复',
                () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CommunityPage(store: store, feedbackOnly: true),
                  ),
                ),
              ),
              item(
                Icons.info_outline,
                '关于蓝笔',
                '开源你的学习过程',
                () => showAboutDialog(
                  context: context,
                  applicationName: 'Blue-note / 蓝笔',
                  applicationVersion: '0.22.0',
                  children: const [
                    Text(
                      '个人学习创造知识，开源协作完善知识。题目、知识卡片和复习可离线使用；社区需连接你配置的后台。识别结果请核对后保存。',
                    ),
                  ],
                ),
              ),
            ]),
          ],
        ),
      );
    },
  );
}
