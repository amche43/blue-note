import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'store.dart';
import 'ink_page.dart';
import 'ink_view.dart';
import 'question_photos.dart';

class KnowledgePage extends StatefulWidget {
  final StudyStore store;
  final String id;
  const KnowledgePage({super.key, required this.store, required this.id});
  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  bool revealed = false;
  @override
  Widget build(BuildContext context) {
    final q = widget.store.questions[widget.id]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识卡片'),
        actions: [
          IconButton(
            tooltip: '编辑知识卡片',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => InkPage(store: widget.store, id: widget.id),
                ),
              );
              if (!mounted || !context.mounted) return;
              if (widget.store.questions[widget.id]?['deleted'] == true) {
                Navigator.pop(context);
                return;
              }
              setState(() => revealed = false);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            q['title'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${q['subject']} · ${q['notebookTitle']}'),
          const SizedBox(height: 24),
          const Text('先在心里说一遍内容和适用条件，再展开核对。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() => revealed = !revealed),
            child: Text(revealed ? '收起，再回想一次' : '展开知识内容'),
          ),
          if (revealed) ...[
            const SizedBox(height: 20),
            if ((q['canvas'] as String? ?? '').isNotEmpty)
              InkPreview(q['canvas'] as String),
            SelectableText(q['prompt'] as String),
            QuestionPhoto(q['questionPhoto'] as String? ?? '', label: '知识内容照片'),
            QuestionPhoto(q['answerPhoto'] as String? ?? '', label: '理解与解答照片'),
            if ((q['formula'] as String).isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  q['formula'] as String,
                  onErrorFallback: (_) =>
                      SelectableText(q['formula'] as String),
                ),
              ),
            ...{
                  'answer': '理解与记忆方法',
                  'trigger': '使用线索',
                  'action': '记忆线索',
                  'conditions': '适用条件',
                  'pitfall': '容易混淆',
                  'source': '来源',
                  'firstThought': '我的第一反应',
                  'summary': '一句话总结',
                }.entries
                .where((e) => (q[e.key] as String? ?? '').isNotEmpty)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SelectableText('${e.value}\n${q[e.key]}'),
                  ),
                ),
          ],
          const SizedBox(height: 24),
          const Text('自己整理的内容。展开不计为掌握；公开分享请到共享题库选择这张卡片。'),
        ],
      ),
    );
  }
}
