import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'store.dart';
import 'domain.dart';

/// Serialized local writes prevent a delayed autosave from recreating a saved draft.
class EditorDraft extends ChangeNotifier with WidgetsBindingObserver {
  final StudyStore store;
  final String key;
  final Json Function() snapshot;
  Timer? timer;
  Future<void> writes = Future.value();
  bool active = false, closed = false;
  bool hasChanges = false;
  int revision = 0;
  String status = '草稿仅保存在本机';
  EditorDraft(this.store, this.key, this.snapshot) {
    WidgetsBinding.instance.addObserver(this);
  }
  void schedule() {
    if (!active || closed) return;
    hasChanges = true;
    revision++;
    timer?.cancel();
    status = '草稿待保存';
    notifyListeners();
    timer = Timer(const Duration(milliseconds: 600), () {
      flush();
    });
  }

  Future<bool> flush() async {
    timer?.cancel();
    if (!active || closed || !hasChanges) return true;
    final savedRevision = revision;
    final raw = jsonEncode({
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': snapshot(),
    });
    var success = true;
    writes = writes.then((_) async {
      try {
        if (utf8.encode(raw).length > 20 * 1024 * 1024) {
          throw const FormatException('草稿图片过大');
        }
        await store.setting(key, raw);
        if (!closed) {
          if (savedRevision == revision) status = '草稿已保存在本机';
          notifyListeners();
        }
      } catch (_) {
        success = false;
        if (!closed) {
          status = '草稿未保存，请不要退出，稍后重试';
          notifyListeners();
        }
      }
    });
    await writes;
    return success;
  }

  Future<void> settle() async {
    timer?.cancel();
    await writes;
  }

  Future<void> discard() async {
    final wasActive = active;
    active = false;
    try {
      await settle();
      await store.db.delete('settings', where: 'key=?', whereArgs: [key]);
      await store.refresh();
      hasChanges = false;
    } catch (_) {
      active = wasActive;
      rethrow;
    }
  }

  Future<bool> recover(
    BuildContext context,
    void Function(Json) restore,
  ) async {
    final raw = store.settings[key];
    if (raw == null) {
      active = true;
      return true;
    }
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('继续上次的草稿？'),
        content: const Text('这份内容尚未正式保存。恢复后请核对再保存，尤其是原条目在此期间可能已经修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('删除旧草稿'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复草稿'),
          ),
        ],
      ),
    );
    if (keep == null) return false;
    if (keep) {
      restore((jsonDecode(raw) as Json)['data'] as Json);
      hasChanges = true;
      status = '已恢复草稿，尚未正式保存';
    } else {
      await discard();
    }
    active = true;
    notifyListeners();
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      flush();
    }
  }

  @override
  void dispose() {
    closed = true;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

Widget draftStatus(EditorDraft draft) => ListenableBuilder(
  listenable: draft,
  builder: (context, _) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      draft.status,
      style: TextStyle(
        fontSize: 12,
        color: draft.status.contains('未保存')
            ? Colors.deepOrange
            : Colors.blueGrey,
      ),
    ),
  ),
);

Future<String?> draftExit(BuildContext context) => showDialog<String>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('先把这份内容留下来？'),
    content: const Text('保存草稿后，下次从同一录入入口继续。草稿不会公开，也不计入学习成就。'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('继续编辑'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(ctx, 'discard'),
        child: const Text('放弃修改'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, 'keep'),
        child: const Text('保留草稿并退出'),
      ),
    ],
  ),
);
