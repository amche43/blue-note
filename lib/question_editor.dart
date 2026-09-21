import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'questions.dart';
import 'store.dart';
import 'notebooks.dart';
import 'photo_import.dart';
import 'question_photos.dart';
import 'entry_history.dart';
import 'editor_draft.dart';
import 'package:flutter/foundation.dart';

class QuestionEditor extends StatefulWidget {
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
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late Json original;
  late final EditorDraft draft;
  Json? capture;
  bool get knowledge => fields['contentKind']!.text == 'knowledge';
  List<Lesson>? suggestions;
  bool busy = false, changed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    original = widget.id == null
        ? {
            ...blankQuestion(),
            'notebookId': widget.notebookId ?? '',
            'notebookTitle': widget.notebookTitle ?? '',
            'contentKind': widget.knowledge ? 'knowledge' : 'question',
          }
        : validateQuestion(widget.store.questions[widget.id]);
    fields = {
      for (final key in questionLimits.keys)
        key: TextEditingController(text: original[key] as String),
    };
    draft = EditorDraft(
      widget.store,
      'editDraft:${widget.id ?? 'new-${widget.knowledge}-${widget.notebookId ?? ''}'}',
      () => {
        'fields': {for (final e in fields.entries) e.key: e.value.text},
        'base': original,
        'capture': capture,
      },
    );
    for (final c in fields.values) {
      c.addListener(draft.schedule);
    }
    busy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final ready = await draft.recover(context, (data) {
          for (final e in (data['fields'] as Json).entries) {
            fields[e.key]?.text = e.value as String;
          }
          original = data['base'] as Json;
          capture = data['capture'] as Json?;
          changed = true;
        });
        if (!mounted) return;
        if (!ready) {
          finish(null);
          return;
        }
        setState(() => busy = false);
      } catch (_) {
        if (mounted) {
          setState(() {
            busy = false;
            error = '草稿暂时无法恢复，原草稿仍保留。';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    draft.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    int lines = 1,
    bool required = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('question-$key'),
      controller: fields[key],
      minLines: lines,
      maxLines: lines + 3,
      enabled: !busy,
      maxLength: questionLimits[key],
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) {
        setState(() => changed = true);
      },
      validator: (value) =>
          required && (value?.trim().isEmpty ?? true) ? '请填写$label' : null,
    ),
  );

  Future<bool> confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> leave() async {
    if (busy) return;
    if (!changed) {
      if (mounted) finish(null);
      return;
    }
    final action = await draftExit(context);
    if (action == null || !mounted) return;
    setState(() => busy = true);
    try {
      if (action == 'keep') {
        if (!await draft.flush()) {
          if (mounted) setState(() => busy = false);
          return;
        }
      } else {
        await draft.discard();
      }
      if (mounted) finish(null);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '草稿未能处理，请留在页面重试';
        });
      }
    }
  }

  void finish(String? value) {
    draft.active = false;
    setState(() {
      changed = false;
      busy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, value);
    });
  }

  Future<void> save({bool asCopy = false}) async {
    if (busy || !form.currentState!.validate()) return;
    draft.active = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await draft.settle();
      if (!asCopy &&
          widget.id != null &&
          !mapEquals(widget.store.questions[widget.id], original)) {
        throw const FormatException('原条目在此期间已修改，请另存为新条目，避免覆盖新内容。');
      }
      final id = await widget.store.saveQuestion(
        {
          for (final e in fields.entries) e.key: e.value.text,
          'deleted': false,
          if (asCopy) 'questionNumber': '',
        },
        id: asCopy ? null : widget.id,
        capture: capture,
        clearDraftKey: draft.key,
        expected: asCopy || widget.id == null ? null : original,
      );
      if (mounted) finish(id);
    } catch (e) {
      draft.active = true;
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException ? e.message : '未能保存，请重试。编辑内容仍在这里。';
        });
      }
    }
  }

  Future<void> useSuggestion(Lesson lesson) async {
    const keys = ['trigger', 'action', 'conditions', 'pitfall'];
    if (keys.any((key) => fields[key]!.text.trim().isNotEmpty) &&
        !await confirm('替换已填写的关键点？', '将引用这道参考例题的四项总结，请核对是否适用于你的题目。', '替换')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final key in keys) {
        fields[key]!.text = lesson.blue[key] as String;
      }
      changed = true;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<String>(
    canPop: !changed && !busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          knowledge
              ? '编辑知识卡片'
              : widget.id == null
              ? '添加我的题目'
              : '编辑题目',
        ),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : leave,
        ),
        actions: [
          IconButton(
            tooltip: '保存题目',
            icon: const Icon(Icons.check),
            onPressed: busy ? null : save,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    knowledge ? '把必须记住的知识，整理成自己的话。' : '先把题目留住，再慢慢补上想法。',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('默认只保存在自己的题库。保存不会公开发布。'),
                  draftStatus(draft),
                  const SizedBox(height: 24),
                  if (widget.id != null)
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntryHistory(
                                    store: widget.store,
                                    id: widget.id!,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              if (!changed &&
                                  draft.active &&
                                  !mapEquals(
                                    widget.store.questions[widget.id],
                                    original,
                                  )) {
                                draft.active = false;
                                try {
                                  await draft.discard();
                                  if (!mounted) return;
                                  original = validateQuestion(
                                    widget.store.questions[widget.id],
                                  );
                                  for (final e in fields.entries) {
                                    e.value.text = original[e.key] as String;
                                  }
                                } catch (_) {
                                  error = '历史已更新，但编辑器暂未刷新，请退出后重新打开。';
                                } finally {
                                  draft.active = true;
                                }
                              }
                              if (mounted) setState(() {});
                            },
                      icon: const Icon(Icons.history),
                      label: const Text('原图、录入记录与修改历史'),
                    ),
                  if (widget.id == null)
                    DropdownButtonFormField<String>(
                      initialValue: fields['notebookId']!.text,
                      decoration: const InputDecoration(labelText: '保存到错题本'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('暂不分本')),
                        ...notebooks(widget.store).entries
                            .where(
                              (e) =>
                                  isKnowledgeBook(widget.store, e.key) ==
                                  knowledge,
                            )
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            ),
                      ],
                      onChanged: busy
                          ? null
                          : (id) => setState(() {
                              fields['notebookId']!.text = id ?? '';
                              fields['notebookTitle']!.text =
                                  notebooks(widget.store)[id] ?? '';
                              fields['questionNumber']!.clear();
                              changed = true;
                            }),
                    ),
                  if (widget.id != null &&
                      fields['notebookId']!.text.isNotEmpty)
                    Text(
                      '${fields['notebookTitle']!.text} · 第${fields['questionNumber']!.text}题（固定题号）',
                    ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final result = await Navigator.push<Json>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PhotoImportPage(store: widget.store),
                              ),
                            );
                            if (result == null || !mounted) return;
                            if ((fields['prompt']!.text.trim().isNotEmpty ||
                                    fields['questionPhoto']!.text.isNotEmpty) &&
                                !await confirm(
                                  '替换现有题干？',
                                  '识别草稿将替换当前题干，请确认。',
                                  '替换',
                                )) {
                              return;
                            }
                            if (mounted) {
                              setState(() {
                                fields['prompt']!.text =
                                    result['text'] as String;
                                fields['questionPhoto']!.text =
                                    result['photo'] as String? ?? '';
                                if (fields['title']!.text.trim().isEmpty) {
                                  fields['title']!.text =
                                      result['title'] as String? ?? '';
                                }
                                capture = result['capture'] as Json;
                                changed = true;
                              });
                            }
                          },
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('拍照 / 从相册识题'),
                  ),
                  field(
                    'title',
                    knowledge ? '知识点名称 / 正面提示' : '题目名称（可留空）',
                    hint: '例如：一道没想到对称换元的积分题',
                  ),
                  if (fields['questionPhoto']!.text.isNotEmpty) ...[
                    QuestionPhoto(fields['questionPhoto']!.text),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              fields['questionPhoto']!.clear();
                              changed = true;
                            }),
                      child: const Text('移除题目照片'),
                    ),
                  ],
                  field('subject', '科目', required: true),
                  field('chapter', '章节（可选）'),
                  field(
                    'prompt',
                    knowledge ? '需要记住的内容（展开后显示）' : '完整题干',
                    lines: 4,
                    hint: '写清已知条件和要求，也可以粘贴已识别的文字',
                  ),
                  ExpansionTile(
                    title: Text(knowledge ? '公式与解释（可稍后补充）' : '公式与解答（可稍后补充）'),
                    initiallyExpanded: true,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('添加 / 识别答案照片'),
                        onPressed: busy
                            ? null
                            : () async {
                                final result = await Navigator.push<Json>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PhotoImportPage(
                                      store: widget.store,
                                      answer: true,
                                    ),
                                  ),
                                );
                                if (result == null || !mounted) return;
                                if ((fields['answer']!.text.isNotEmpty ||
                                        fields['answerPhoto']!
                                            .text
                                            .isNotEmpty) &&
                                    !await confirm(
                                      '替换现有答案？',
                                      '新的答案照片或识别正文将替换当前答案。',
                                      '替换',
                                    )) {
                                  return;
                                }
                                if (!mounted) return;
                                setState(() {
                                  fields['answer']!.text =
                                      result['text'] as String;
                                  fields['answerPhoto']!.text =
                                      result['photo'] as String? ?? '';
                                  changed = true;
                                  capture = {
                                    ...?capture,
                                    'answer_capture': result['capture'],
                                  };
                                  draft.schedule();
                                });
                              },
                      ),
                      if (fields['answerPhoto']!.text.isNotEmpty) ...[
                        QuestionPhoto(
                          fields['answerPhoto']!.text,
                          label: '答案照片',
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  fields['answerPhoto']!.clear();
                                  changed = true;
                                }),
                          child: const Text('移除答案照片'),
                        ),
                      ],
                      field('formula', '公式（LaTeX，可选）', lines: 2),
                      field(
                        'answer',
                        knowledge ? '理解、例子与记忆方法' : '解答与思路',
                        lines: 4,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => suggestions = suggestLessons(
                        '${fields['prompt']!.text} ${fields['formula']!.text}',
                        widget.store.bundledLessons,
                      ),
                    ),
                    icon: const Icon(Icons.manage_search),
                    label: const Text('查找相关知识点'),
                  ),
                  if (suggestions != null) ...[
                    const Text(
                      '以下仅按关键词匹配参考例题，不代表已经判断出解法。引用前请核对适用条件。',
                      style: TextStyle(fontSize: 13),
                    ),
                    if (suggestions!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('现有知识库暂未匹配到。可以直接填写自己的总结。'),
                      ),
                    ...suggestions!.map(
                      (lesson) => Card(
                        child: ExpansionTile(
                          title: Text(lesson.title),
                          subtitle: Text('${lesson.subject} · 待你核对'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '看到什么：${lesson.blue['trigger']}\n关键动作：${lesson.blue['action']}\n使用条件：${lesson.blue['conditions']}\n容易误用：${lesson.blue['pitfall']}',
                                  ),
                                  TextButton(
                                    onPressed: () => useSuggestion(lesson),
                                    child: const Text('引用这组关键点'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    '我的关键点',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  field('trigger', '看到什么线索', lines: 2),
                  field('action', knowledge ? '记忆线索' : '应该想到哪一步', lines: 2),
                  field('conditions', '适用条件', lines: 2),
                  field('pitfall', '容易误用的地方', lines: 2),
                  field('source', '题目来源与署名（可选）', lines: 2),
                  ExpansionTile(
                    title: const Text('我的思考过程'),
                    children: [
                      field('firstThought', '我的第一反应', lines: 2),
                      field('errorReason', '错误原因', lines: 2),
                      field('summary', '一句话总结', lines: 2),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (widget.id != null &&
                      !mapEquals(widget.store.questions[widget.id], original))
                    OutlinedButton(
                      onPressed: busy ? null : () => save(asCopy: true),
                      child: const Text('另存为新条目'),
                    ),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(
                      busy
                          ? '正在保存…'
                          : knowledge
                          ? '保存知识卡片'
                          : '保存到我的题库',
                    ),
                  ),
                  if (widget.id != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!await confirm(
                                '删除这道自建题目？',
                                '会从自己的题库移除，已分享给别人的副本不受影响。',
                                '删除',
                              )) {
                                return;
                              }
                              if (!mounted) return;
                              setState(() => busy = true);
                              draft.active = false;
                              try {
                                await draft.settle();
                                await widget.store.deleteQuestion(
                                  widget.id!,
                                  clearDraftKey: draft.key,
                                );
                                if (mounted) finish('deleted');
                              } catch (_) {
                                draft.active = true;
                                if (mounted) {
                                  setState(() {
                                    busy = false;
                                    error = '删除失败，请重试。';
                                  });
                                }
                              }
                            },
                      child: const Text('删除这道题'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
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
