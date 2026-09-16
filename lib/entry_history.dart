import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'history_restore.dart';

class EntryHistory extends StatefulWidget {
  final StudyStore store;
  final String id;
  const EntryHistory({super.key, required this.store, required this.id});
  @override
  State<EntryHistory> createState() => _EntryHistoryState();
}

class _EntryHistoryState extends State<EntryHistory> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(update);
    super.dispose();
  }

  late final data = widget.store.db.query(
    'capture_records',
    where: 'lesson_id=?',
    whereArgs: [widget.id],
  );
  @override
  Widget build(BuildContext context) {
    final revisions =
        widget.store.events
            .where((e) => e.type == 'question' && e.lessonId == widget.id)
            .toList()
          ..sort(compareEvents);
    return Scaffold(
      appBar: AppBar(title: const Text('录入与修改历史')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('原始识别与确认记录', style: TextStyle(fontSize: 22)),
          FutureBuilder(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('录入记录暂时无法读取');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) {
                return const Text('这条内容没有保存在本机的照片识别记录。');
              }
              final record =
                  jsonDecode(snapshot.data!.first['data'] as String) as Json;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (record['source_image'] is String)
                    Image.memory(
                      base64Decode(record['source_image'] as String),
                      height: 300,
                      fit: BoxFit.contain,
                    ),
                  const Text('录入时的图片（已压缩），仅保存在当前设备。'),
                  ExpansionTile(
                    title: const Text('OCR 原始结果'),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(record['ocr_raw']),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('AI 结构化结果'),
                    children: [
                      Text(
                        record['ai_parsed'] == null
                            ? '本次没有调用结构化模型，没有生成推测结果。'
                            : const JsonEncoder.withIndent(
                                '  ',
                              ).convert(record['ai_parsed']),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('录入时的用户确认结果'),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(record['user_confirmed']),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('修改历史', style: TextStyle(fontSize: 22)),
          const Text('逐项对照历史与当前已保存内容，再选择需要恢复的字段。恢复会新增版本，保留原有历史。'),
          ...revisions.reversed.map(
            (e) => ExpansionTile(
              key: ValueKey(e.id),
              title: Text(
                DateTime.fromMillisecondsSinceEpoch(
                  e.at,
                ).toString().substring(0, 16),
              ),
              subtitle: Text(e.payload['title'] as String),
              children: [
                if (e.payload['deleted'] == true) const Text('这是一条删除记录，仅供查阅。'),
                if (e.payload['deleted'] != true &&
                    widget.store.questions[widget.id]?['deleted'] == false)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final restored = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryRestorePage(
                            store: widget.store,
                            revision: e,
                            current: {...widget.store.questions[widget.id]!},
                          ),
                        ),
                      );
                      if (restored == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已恢复所选内容，并保存为新版本')),
                        );
                      }
                    },
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('与当前对照 / 选择恢复'),
                  ),
                ...historyFields.entries
                    .where(
                      (f) => (e.payload[f.key] as String? ?? '').isNotEmpty,
                    )
                    .map(
                      (f) => ListTile(
                        title: Text(f.value),
                        subtitle: SelectableText(e.payload[f.key] as String),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
