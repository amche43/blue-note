import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'questions.dart';
import 'store.dart';
import 'ink_page.dart';

// Compatibility route for older links; all editing now uses the canvas.
class QuestionEditor extends StatelessWidget {
  final StudyStore store;
  final bool knowledge;
  final String? id, notebookId, notebookTitle;
  const QuestionEditor({
    super.key,
    required this.store,
    this.id,
    this.notebookId,
    this.notebookTitle,
    this.knowledge = false,
  });
  @override
  Widget build(BuildContext context) => InkPage(
    store: store,
    id: id,
    notebookId: notebookId,
    notebookTitle: notebookTitle,
  );
}

Future<void> shareQuestionDialog(
  BuildContext context,
  StudyStore store,
  String id,
) async {
  final question = store.questions[id]!;
  final author = TextEditingController(text: '匿名分享者');
  bool consent = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('分享题目包'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  question['prompt'] as String,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                const Text(
                  '将包含正文、公式、解答、关键点、思考过程和来源。私人蓝笔笔记、识别原图与作答记录不会包含在内。\n这一步只复制题目包，不会上传服务器。',
                ),
                ...['firstThought', 'errorReason', 'summary']
                    .where((k) => (question[k] as String? ?? '').isNotEmpty)
                    .map(
                      (k) => Text(
                        '${{'firstThought': '我的第一反应', 'errorReason': '错误原因', 'summary': '一句话总结'}[k]}：${question[k]}',
                      ),
                    ),
                const SizedBox(height: 16),
                TextField(
                  controller: author,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '分享署名'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consent,
                  title: const Text('我同意将上述题目内容分享给他人'),
                  onChanged: (v) => setState(() => consent = v ?? false),
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: !consent
                ? null
                : () async {
                    try {
                      final raw = encodeQuestionPackage(
                        id,
                        question,
                        consent: consent,
                        author: author.text,
                      );
                      await Clipboard.setData(ClipboardData(text: raw));
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('题目包已复制。对方可在“导入题目包”中粘贴。'),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        setState(() => error = '未能复制，请检查署名后重试。');
                      }
                    }
                  },
            child: const Text('同意并复制题目包'),
          ),
        ],
      ),
    ),
  );
  // Disposing after the dialog's route transition avoids an attached controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  author.dispose();
}

Future<String?> importQuestionDialog(
  BuildContext context,
  StudyStore store,
) async {
  final controller = TextEditingController();
  Json? preview;
  String? error;
  bool busy = false;
  final id = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('导入题目包'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 200000,
                  decoration: const InputDecoration(hintText: '粘贴别人分享的完整题目包'),
                  onChanged: (_) => setState(() {
                    preview = null;
                    error = null;
                  }),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '分享者：${preview!['author']}\n${(preview!['question'] as Json)['title']}\n${(preview!['question'] as Json)['prompt']}',
                  ),
                ],
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () {
                    try {
                      final parsed = decodeQuestionPackage(controller.text);
                      setState(() {
                        preview = parsed;
                        error = null;
                      });
                    } catch (_) {
                      setState(() => error = '题目包不完整或格式不受支持，请重新复制。');
                    }
                  },
            child: const Text('预览题目'),
          ),
          FilledButton(
            onPressed: preview == null || busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final id = await store.importQuestionPackage(
                        controller.text,
                      );
                      if (context.mounted) Navigator.pop(context, id);
                    } catch (_) {
                      if (context.mounted) {
                        setState(() {
                          busy = false;
                          error = '导入失败，原题库未被覆盖。';
                        });
                      }
                    }
                  },
            child: const Text('保存私人副本'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return id;
}
