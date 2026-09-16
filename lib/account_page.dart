import 'dart:convert';
import 'package:flutter/material.dart';
import 'brand.dart';
import 'community.dart';
import 'store.dart';
import 'avatar_page.dart';

class AccountPage extends StatefulWidget {
  final StudyStore store;
  const AccountPage({super.key, required this.store});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final connection = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false, visible = false;
  String error = '';
  int avatar = 0;
  bool customAvatar = false;
  @override
  void initState() {
    super.initState();
    connection.text = widget.store.settings['community'] ?? '';
  }

  @override
  void dispose() {
    for (final c in [connection, username, password, name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final config = CommunityClient.parse(
        connection.text,
        allowAnonymous: true,
      );
      final result = await CommunityClient(config)
          .request('POST', '/v1/auth/${register ? 'register' : 'login'}', {
            'username': username.text.trim(),
            'password': password.text,
            if (register) 'name': name.text.trim(),
            if (register) 'avatar': avatar,
          });
      config['token'] = result['token'];
      await widget.store.setting('community', jsonEncode(config));
      await widget.store.setting('avatar', '${result['avatar'] ?? 0}');
      await widget.store.setting('profileName', result['name'] as String);
      await widget.store.setting(
        'avatarImage',
        result['avatarImage'] as String? ?? '',
      );
      password.clear();
      if (mounted && customAvatar && register) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => AvatarPage(store: widget.store)),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '暂时无法登录，请检查后台连接后重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('蓝笔账号')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        children: [
          const Center(child: BlueMascot(width: 100)),
          const SizedBox(height: 20),
          Text(
            register ? '开启你的学习共创' : '欢迎回到蓝笔',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
              color: Color(0xff172952),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '开源你的学习过程。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 28),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('登录')),
              ButtonSegment(value: true, label: Text('注册')),
            ],
            selected: {register},
            onSelectionChanged: busy
                ? null
                : (s) => setState(() => register = s.first),
          ),
          const SizedBox(height: 20),
          if (register)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BlueAvatar(index: avatar, width: 52),
                title: const Text('选择头像'),
                subtitle: Text(
                  customAvatar ? '自定义头像 · 注册后上传审核' : avatarNames[avatar],
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () async {
                        final chosen = await chooseBlueAvatar(context, avatar);
                        if (chosen != null && mounted) {
                          setState(() {
                            customAvatar = chosen == -1;
                            if (!customAvatar) avatar = chosen;
                          });
                        }
                      },
              ),
            ),
          if (register)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '注册后也可在“我的”上传照片头像，审核通过后使用。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: username,
                  enabled: !busy,
                  autofillHints: const [AutofillHints.username],
                  maxLength: 40,
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: '账号',
                    hintText: '字母、数字或下划线',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                if (register)
                  TextField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      counterText: '',
                      labelText: '昵称',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: !visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 128,
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: '密码',
                    hintText: '至少8个字符',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: visible ? '隐藏密码' : '显示密码',
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ExpansionTile(
            initiallyExpanded: connection.text.isEmpty,
            tilePadding: EdgeInsets.zero,
            title: const Text('本机后台连接', style: TextStyle(fontSize: 14)),
            children: [
              const Text(
                '首次使用需粘贴电脑生成的连接配置，账号保存在这台电脑的后台。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              TextField(
                controller: connection,
                enabled: !busy,
                obscureText: true,
                maxLines: 1,
                decoration: const InputDecoration(labelText: '连接配置（含证书）'),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? '正在连接…'
                  : register
                  ? '创建账号'
                  : '登录',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '当前为本机测试账号；重新登录会替换该账号上一次的登录状态。',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityPage(store: widget.store),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('使用已有测试连接 / 管理发布'),
          ),
        ],
      ),
    ),
  );
}
