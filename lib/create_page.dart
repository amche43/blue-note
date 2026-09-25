import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'notebooks.dart';
import 'ink_page.dart';

class CreatePage extends StatelessWidget {
  final StudyStore store;
  final VoidCallback createBook;
  final Future<void> Function(Lesson) openLesson;
  const CreatePage({
    super.key,
    required this.store,
    required this.createBook,
    required this.openLesson,
  });
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('create-page'),
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        '从一本笔记开始',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      const Text(
        '笔记本 → 章节 → 页面。文字、照片和思路，都留在画布里。',
        style: TextStyle(color: Colors.blueGrey, height: 1.7),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        onPressed: createBook,
        icon: const Icon(Icons.add),
        label: const Text('创建笔记本'),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AllNotebooksPage(store: store, openLesson: openLesson),
          ),
        ),
        icon: const Icon(Icons.auto_stories_outlined),
        label: const Text('打开我的笔记本'),
      ),
      if (store.questions.values.any(
        (q) => q['notebookId'] == '' && q['deleted'] == false,
      )) ...[
        const SizedBox(height: 32),
        const Text(
          '待归档的页面',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        for (final e in store.questions.entries.where(
          (e) => e.value['notebookId'] == '' && e.value['deleted'] == false,
        ))
          ListTile(
            title: Text(e.value['title'] as String),
            leading: const Icon(Icons.description_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => InkPage(store: store, id: e.key),
              ),
            ),
          ),
      ],
    ],
  );
}
