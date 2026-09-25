import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';
import 'full_backup.dart';

class BackupPage extends StatefulWidget {
  final StudyStore store;
  final VoidCallback legacyExport, legacyImport;
  const BackupPage({
    super.key,
    required this.store,
    required this.legacyExport,
    required this.legacyImport,
  });
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const channel = MethodChannel('blue_note/backup');
  bool busy = false;
  String notice = '';
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      notice = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => notice = e is FormatException
              ? e.message
              : e is PlatformException
              ? e.message ?? '文件操作未完成'
              : '操作失败，原有记录未被清空，请检查备份文件',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    final raw = await widget.store.fullBackup();
    final saved = await channel.invokeMethod<bool>('save', {
      'bytes': Uint8List.fromList(utf8.encode(raw)),
      'name':
          'blue-note-${DateTime.now().toIso8601String().substring(0, 10)}.bluenote',
    });
    if (mounted) {
      setState(() => notice = saved == true ? '完整备份已保存到所选位置' : '已取消保存');
    }
  }

  Future<void> restore() async {
    final bytes = await channel.invokeMethod<Uint8List>('open');
    if (bytes == null) return;
    final raw = utf8.decode(bytes);
    final backup = FullBackup.decode(raw);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复内容'),
        content: Text(
          '${backup.summary}\n\n合并学习历史；同名编号的本子设置、收藏和图片保留本机版本。若记录编号冲突，整次导入取消。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('合并恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await widget.store.restoreFull(raw);
    if (mounted) setState(() => notice = '恢复完成，新增 $count 条学习记录；已补充缺少的本子设置和图片。');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('笔记本备份')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(
          Icons.inventory_2_outlined,
          size: 52,
          color: Color(0xff2878f0),
        ),
        const SizedBox(height: 20),
        const Text(
          '把学习成果带走',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '保存这台设备的全部笔记本内容、空本子、题目原图与识别记录、笔记、作答历史和收藏。账号口令、聊天和服务端内容不在此备份内。',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : () => run(export),
          icon: const Icon(Icons.save_alt),
          label: const Text('保存完整备份文件'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run(restore),
          icon: const Icon(Icons.folder_open),
          label: const Text('选择备份文件恢复'),
        ),
        const SizedBox(height: 12),
        const Text(
          '文件含私人笔记与照片，未加密，请保存在自己的安全位置。当前支持不超过 64MB 的备份。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        if (busy) const LinearProgressIndicator(),
        if (notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(notice),
          ),
        const SizedBox(height: 24),
        const Divider(),
        ListTile(
          title: const Text('兼容旧版文字备份'),
          subtitle: const Text('仅学习记录，不包含图片和空本子'),
          trailing: const Icon(Icons.notes),
          onTap: busy ? null : widget.legacyExport,
        ),
        TextButton(
          onPressed: busy ? null : widget.legacyImport,
          child: const Text('粘贴旧版备份恢复'),
        ),
      ],
    ),
  );
}
