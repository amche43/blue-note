import 'package:flutter/material.dart';
import 'achievements.dart';
import 'brand.dart';
import 'community.dart';
import 'domain.dart';
import 'store.dart';

class LearningProfilePage extends StatefulWidget {
  final StudyStore? store;
  final CommunityClient? client;
  final String? userId;
  const LearningProfilePage({super.key, this.store, this.client, this.userId});
  @override
  State<LearningProfilePage> createState() => _LearningProfilePageState();
}

class _LearningProfilePageState extends State<LearningProfilePage> {
  Json? profile;
  String error = '';
  bool busy = false, earnedOnly = false;
  int tab = 0;
  bool get own => widget.userId == null;
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
      final raw = widget.store?.settings['community'];
      final client =
          widget.client ??
          (raw == null ? null : CommunityClient(CommunityClient.parse(raw)));
      if (client == null) {
        if (mounted) setState(() => error = '连接账号后可查看公开学习履历。');
        return;
      }
      final id =
          widget.userId ??
          (await client.request('GET', '/v1/me'))['id'] as String;
      final result = await client.request('GET', '/v1/profiles/$id');
      if (mounted) setState(() => profile = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '公开履历暂时无法读取，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void details(Achievement a, int? value) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(a.english, style: const TextStyle(color: Colors.blueGrey)),
              const SizedBox(height: 16),
              Text(a.rule),
              const SizedBox(height: 20),
              ...List.generate(
                4,
                (i) => ListTile(
                  leading: AchievementBadge(
                    icon: a.icon,
                    level: i + 1,
                    size: 42,
                  ),
                  title: Text('${tierNames[i + 1]} · ${a.goals[i]} ${a.unit}'),
                  trailing: value != null && value >= a.goals[i]
                      ? const Icon(Icons.check_circle, color: Color(0xff2878f0))
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value == null
                    ? '此指标需要对应功能和可核实数据，目前未计奖。'
                    : '当前有效成果：$value ${a.unit}。按当前有效内容核算，撤回、删除或未采纳会影响进度。',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = own && tab == 0;
    final values = local && widget.store != null
        ? localAchievements(widget.store!)
        : Map<String, int>.from(profile?['counts'] as Map? ?? {});
    final items = achievements
        .where((a) => !earnedOnly || a.level(values[a.id] ?? 0) > 0)
        .toList();
    final earned = achievements
        .where((a) => a.level(values[a.id] ?? 0) > 0)
        .length;
    final name = own
        ? (widget.store?.settings['profileName'] ?? '我的学习履历')
        : (profile?['name'] ?? '学习者');
    return Scaffold(
      appBar: AppBar(
        title: Text(own ? '我的成就' : '开放学习履历'),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            tooltip: '刷新学习履历',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            children: [
              BlueAvatar(
                index: profile?['avatar'] as int? ?? 0,
                photo: profile?['avatarImage'] as String?,
                width: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Open Your Learning.',
                      style: TextStyle(color: Color(0xff2878f0)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            '让贡献成为你的学习履历',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            local
                ? '本机学习记录，仅自己可见。公开履历由后台单独核算，不上传私人笔记。'
                : '公开内容与已核实的协作成果；不包含私人学习记录。',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          if (own) ...[
            const SizedBox(height: 18),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('我的学习')),
                ButtonSegment(value: 1, label: Text('公开履历')),
              ],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            ),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error),
            ),
          const SizedBox(height: 20),
          Text(
            '持续建设 ${values['momentum'] ?? 0} 周 · 达成 $earned 类成就',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(
              52,
              (i) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i < (values['momentum'] ?? 0)
                      ? const Color(0xff2878f0)
                      : const Color(0xffe5eefb),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const Text(
            '过去 52 周有效周数 · 非连续签到',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('只看已达成'),
            value: earnedOnly,
            onChanged: (v) => setState(() => earnedOnly = v),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('从一条有自己理解的记录开始。'),
            ),
          ...items.map((a) {
            final value = values[a.id];
            final level = a.level(value ?? 0);
            final next = level < 4 ? a.goals[level] : a.goals.last;
            return InkWell(
              onTap: () => details(a, value),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    AchievementBadge(icon: a.icon, level: level, size: 62),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${a.english} · ${tierNames[level]}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: value == null
                                ? 0
                                : (value / next).clamp(0.0, 1.0),
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value == null
                                ? (local
                                      ? '在公开履历查看'
                                      : '暂无可核实数据')
                                : '$value / $next ${a.unit}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            );
          }),
          const Divider(),
          const Text(
            '特别成就',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            (profile?['specials'] as List? ?? []).contains('one_year')
                ? '一年项目 · 已达成'
                : '一年项目 · 同一本维护满一年后核实',
          ),
          const Text(
            '早期学习者、百人共创、开放知识、社区经典与知识传承：等待上线可核实的历史记录，暂不发放。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}
