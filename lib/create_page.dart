import 'ink_page.dart';
import 'package:flutter/material.dart';
import 'brand.dart';
import 'domain.dart';
import 'store.dart';
import 'entry_composer.dart';
import 'photo_import.dart';
import 'notebooks.dart';
import 'drafts_page.dart';

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
  Future<void> compose(
    BuildContext context, {
    String kind = 'question',
    bool photo = false,
  }) async {
    Json? capture;
    if (photo) {
      capture = await Navigator.push<Json>(
        context,
        MaterialPageRoute(builder: (_) => PhotoImportPage(store: store)),
      );
      if (capture == null || !context.mounted) return;
    }
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryComposer(
          store: store,
          initialKind: kind,
          initialCapture: capture,
        ),
      ),
    );
    if (id != null) {
      final lesson = store.lessons.where((l) => l.id == id).firstOrNull;
      if (lesson != null) await openLesson(lesson);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unfiled = store.lessons
        .where(
          (l) =>
              store.questions[l.id]?['notebookId'] == '' &&
              store.questions[l.id]?['deleted'] == false,
        )
        .toList();
    Widget action(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback tap,
    ) => ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xffedf4ff),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xff2878f0)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: tap,
    );
    return ListView(
      key: const ValueKey('create-page'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
      children: [
        const Text(
          '创造我的学习成果',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xff172952),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '从一道题、一句话、一个新理解开始。',
          style: TextStyle(color: Colors.blueGrey),
        ),
        const SizedBox(height: 24),
        action(
          Icons.draw_outlined,
          '新建手写画布',
          '写字、照片、表格和可点开的思路标记',
          () => Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => InkPage(store: store)),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xffe8f2ff), Color(0xfff5faff)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '先记录，再慢慢理解',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '把纸上的问题，变成自己的学习条目。',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => compose(context, photo: true),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('拍照 / 相册录题'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const BlueMascot(width: 72),
            ],
          ),
        ),
        const SizedBox(height: 24),
        action(
          Icons.library_add_outlined,
          '创建学习本',
          '新建错题本或知识本，给学习一个家',
          createBook,
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => action(
            Icons.drafts_outlined,
            '我的草稿箱',
            '${store.settings.keys.where((k) => k.startsWith('editDraft:')).length} 份待整理 · 继续上次的思考',
            () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => DraftsPage(store: store)),
            ),
          ),
        ),
        action(
          Icons.edit_note,
          '手动记录题目',
          '记录题干、错误原因和关键突破点',
          () => compose(context),
        ),
        action(
          Icons.lightbulb_outline,
          '整理知识卡片',
          '记住公式、概念与自己的理解',
          () => compose(context, kind: 'knowledge'),
        ),
        const SizedBox(height: 20),
        const Divider(),
        Row(
          children: [
            const Expanded(
              child: Text(
                '继续整理',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AllNotebooksPage(store: store, openLesson: openLesson),
                ),
              ),
              child: const Text('我的学习本'),
            ),
          ],
        ),
        Text(
          unfiled.isEmpty
              ? '内容会默认私有。整理完成后，你可以再决定是否公开。'
              : '${unfiled.length} 条内容尚未加入学习本',
          style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
        ),
        ...unfiled
            .take(5)
            .map(
              (l) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SubjectArt(l.subject),
                title: Text(
                  l.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(l.subject),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openLesson(l),
              ),
            ),
        const SizedBox(height: 22),
        const Text(
          '开源你的学习过程。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xff2878f0)),
        ),
      ],
    );
  }
}
