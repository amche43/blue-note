import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'community.dart';
import 'ink_document.dart';
import 'notebook_ui.dart';

List<String> orderedIds(StudyStore store, String key, Iterable<String> ids) {
  final available = ids.toList();
  final raw = store.settings['order:$key'];
  final saved = raw == null
      ? <String>[]
      : (jsonDecode(raw) as List).whereType<String>();
  return {...saved.where(available.contains), ...available}.toList();
}

Future<void> reorderItems(
  StudyStore store,
  String key,
  List<String> ids,
  int from,
  int to,
) async {
  final next = List<String>.of(ids);
  if (to > from) to--;
  next.insert(to, next.removeAt(from));
  await store.setting('order:$key', jsonEncode(next));
}

class NotebookReorderList extends StatelessWidget {
  final List<Widget> children;
  final void Function(int, int) onReorder;
  const NotebookReorderList({
    super.key,
    required this.children,
    required this.onReorder,
  });
  @override
  Widget build(BuildContext context) => ReorderableListView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    onReorderItem: (a, b) => onReorder(a, b > a ? b + 1 : b),
    children: [
      for (var i = 0; i < children.length; i++)
        ReorderableDelayedDragStartListener(
          key: children[i].key,
          index: i,
          child: children[i],
        ),
    ],
  );
}

NoteIconState entryIconState(StudyStore store, String id) {
  final raw = store.settings['publication:$id'];
  if (raw == null) return NoteIconState.local;
  final events =
      store.events
          .where((e) => e.type == 'question' && e.lessonId == id)
          .toList()
        ..sort(compareEvents);
  return events.isNotEmpty &&
          (jsonDecode(raw) as Json)['revision'] == events.last.id
      ? NoteIconState.published
      : NoteIconState.pending;
}

NoteIconState bookIconState(StudyStore store, String book, {String? chapter}) {
  final states = store.questions.entries
      .where(
        (e) =>
            e.value['deleted'] == false &&
            e.value['notebookId'] == book &&
            (chapter == null || e.value['chapter'] == chapter),
      )
      .map((e) => entryIconState(store, e.key))
      .toSet();
  if (states.contains(NoteIconState.pending)) return NoteIconState.pending;
  // A partly published notebook is not fully synchronized.
  if (states.contains(NoteIconState.published)) {
    return states.length == 1 ? NoteIconState.published : NoteIconState.pending;
  }
  return NoteIconState.local;
}

Future<void> uploadEntries(
  BuildContext context,
  StudyStore store,
  List<String> ids,
) async {
  final entries = ids
      .where((id) => store.questions[id]?['deleted'] == false)
      .toList();
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('上传至社区？'),
      content: Text(
        '将公开所选的 ${entries.length} 个知识页，包含照片、笔迹和思路标记。请确认这些内容可以公开分享。空白页会跳过；已有公开版本不会自动覆盖。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认上传'),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  var done = 0, skipped = 0;
  try {
    final raw = store.settings['community'];
    if (raw == null) throw const FormatException('请先在设置中登录并连接本机社区');
    final client = CommunityClient(CommunityClient.parse(raw));
    final support = await client.request('GET', '/v1/photo-capabilities');
    for (final id in entries) {
      final q = store.questions[id]!;
      final canvas = q['canvas'] as String? ?? '';
      if (canvas.isNotEmpty && InkDocument.decode(canvas).elements.isEmpty) {
        skipped++;
        continue;
      }
      if (entryIconState(store, id) == NoteIconState.published) {
        skipped++;
        continue;
      }
      if (canvas.isNotEmpty && support['canvasEntries'] != true) {
        throw const FormatException('请更新本机后台以支持画布');
      }
      final revisions =
          store.events
              .where((e) => e.type == 'question' && e.lessonId == id)
              .toList()
            ..sort(compareEvents);
      final revision = revisions.last.id;
      final result = await client.request('POST', '/v1/questions', {
        'consent': true,
        'requestId': revision,
        'question': q,
      });
      if (result['id'] is! String || result['active'] == false) {
        throw const FormatException('后台未确认公开成功');
      }
      await store.setting(
        'publication:$id',
        jsonEncode({
          'revision': revision,
          'remoteId': result['id'],
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      done++;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传 $done 页，跳过空白或相同版本 $skipped 页')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已上传 $done 页，其余未完成：$e')));
    }
  }
}

Future<void> deleteChapter(
  BuildContext context,
  StudyStore store,
  String book,
  String chapter,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除这个章节？'),
      content: Text('「$chapter」及其知识页将从本机移除，已公开的内容不会下架。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认删除'),
        ),
      ],
    ),
  );
  if (yes != true) return;
  final entries = store.questions.entries
      .where(
        (e) =>
            e.value['deleted'] == false &&
            e.value['notebookId'] == book &&
            (e.value['chapter'] == chapter ||
                (chapter == '未分章' && e.value['chapter'] == '')),
      )
      .toList();
  final key = 'notebook:$book';
  final meta = <String, dynamic>{
    'title': entries.isEmpty ? '笔记本' : entries.first.value['notebookTitle'],
    'kind': 'question',
    ...jsonDecode(store.settings[key] ?? '{}') as Json,
  };
  final now = DateTime.now().millisecondsSinceEpoch;
  try {
    await store.merge(
      [
        for (final e in entries)
          StudyEvent(
            id: newId(),
            lessonId: e.key,
            type: 'question',
            at: store.events
                .where((v) => v.lessonId == e.key)
                .fold<int>(now, (a, v) => v.at >= a ? v.at + 1 : a),
            payload: {...e.value, 'deleted': true},
          ),
      ],
      expectedQuestions: {for (final e in entries) e.key: e.value},
      removeSettings: [key],
      localSettings: {
        key: jsonEncode({
          ...meta,
          'chapters': (meta['chapters'] as List? ?? [])
              .where((c) => c != chapter)
              .toList(),
        }),
      },
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除未完成：$e')));
    }
  }
}

IconData? pageContentIcon(Json q) {
  final raw = q['canvas'] as String? ?? '';
  if (raw.isNotEmpty) {
    try {
      if (InkDocument.decode(raw).elements.any((e) => e.kind == 'image')) {
        return Icons.image_outlined;
      }
    } catch (_) {
      /* Corrupt content remains available for recovery. */
    }
  }
  if ((q['questionPhoto'] as String? ?? '').isNotEmpty) {
    return Icons.image_outlined;
  }
  if ((q['contentType'] as String?) == 'code') return Icons.code;
  if ((q['contentType'] as String?) == 'link') return Icons.link;
  if ((q['prompt'] as String? ?? '').isNotEmpty) {
    return Icons.fact_check_outlined;
  }
  return null;
}
