import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'question_editor.dart';

class MyEntriesPage extends StatelessWidget {
  final StudyStore store;
  final bool knowledge;
  final Future<void> Function(Lesson) open;
  const MyEntriesPage({
    super.key,
    required this.store,
    required this.knowledge,
    required this.open,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final list = store.lessons.where((l) {
        final q = store.questions[l.id];
        return q != null &&
            q['deleted'] == false &&
            (q['contentKind'] == 'knowledge') == knowledge;
      }).toList();
      return Scaffold(
        appBar: AppBar(title: Text(knowledge ? '我的知识卡片' : '我的题目')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(knowledge ? '新建知识卡片' : '记录一道题'),
              onPressed: () => Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      QuestionEditor(store: store, knowledge: knowledge),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (list.isEmpty) const Text('还没有内容。记下一个疑问或理解，从这里开始。'),
            ...list.map(
              (l) => ListTile(
                title: Text(l.title),
                subtitle: Text(l.subject),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(l),
              ),
            ),
          ],
        ),
      );
    },
  );
}
