import 'dart:convert';
import 'domain.dart';
import 'question_photos.dart';
import 'ink_document.dart';

const questionLimits = <String, int>{
  'canvas': 8 * 1024 * 1024,
  'title': 120,
  'subject': 60,
  'chapter': 120,
  'prompt': 18000,
  'formula': 4000,
  'answer': 18000,
  'trigger': 4000,
  'action': 4000,
  'conditions': 4000,
  'pitfall': 4000,
  'source': 1000,
  'origin': 80,
  'notebookId': 40,
  'notebookTitle': 80,
  'questionNumber': 10,
  'contentKind': 16,
  'questionPhoto': photoLimit,
  'answerPhoto': photoLimit,
  'firstThought': 4000,
  'errorReason': 4000,
  'summary': 4000,
};

/// Flat, bounded fields keep backups portable and never execute imported text.
Json validateQuestion(Object? value) {
  if (value is! Json || value['deleted'] is! bool) {
    throw const FormatException('题目格式不正确');
  }
  final result = <String, dynamic>{};
  for (final field in questionLimits.entries) {
    final text =
        value[field.key] ??
        (field.key == 'contentKind'
            ? 'question'
            : [
                'canvas',
                'questionPhoto',
                'answerPhoto',
                'notebookId',
                'notebookTitle',
                'questionNumber',
                'firstThought',
                'errorReason',
                'summary',
              ].contains(field.key)
            ? ''
            : null);
    if (text is! String || text.length > field.value) {
      throw FormatException('${field.key} 内容缺失或过长');
    }
    result[field.key] = text.trim();
  }
  for (final k in ['questionPhoto', 'answerPhoto']) {
    validatePhoto(result[k] as String);
  }
  InkDocument.decode(result['canvas'] as String);
  if ((result['canvas'] as String).isEmpty &&
      (result['prompt'] as String).isEmpty &&
      (result['questionPhoto'] as String).isEmpty) {
    throw const FormatException('请填写题干或添加题目照片');
  }
  if (['title', 'subject'].any((key) => (result[key] as String).isEmpty)) {
    throw const FormatException('请填写题目名称、科目和完整题干');
  }
  result['deleted'] = value['deleted'];
  if (!['question', 'knowledge'].contains(result['contentKind'])) {
    throw const FormatException('内容类型不正确');
  }
  final book = result['notebookId'] as String;
  if (book.isNotEmpty &&
      (!RegExp(r'^book-[a-f0-9]{32}$').hasMatch(book) ||
          (result['notebookTitle'] as String).isEmpty ||
          !RegExp(
            r'^[1-9][0-9]{0,8}$',
          ).hasMatch(result['questionNumber'] as String))) {
    throw const FormatException('错题本或题号格式不正确');
  }
  if (book.isEmpty &&
      (result['notebookTitle'] != '' || result['questionNumber'] != '')) {
    throw const FormatException('题号需要关联错题本');
  }
  return result;
}

Json blankQuestion() => {
  for (final key in questionLimits.keys) key: '',
  'subject': '高等数学',
  'deleted': false,
  'contentKind': 'question',
};

Lesson questionLesson(String id, Json question) {
  final q = validateQuestion(question);
  return Lesson({
    'id': id,
    'title': q['title'],
    'subject': q['subject'],
    'chapter': (q['chapter'] as String).isEmpty ? '我的题目' : q['chapter'],
    'prompt': q['prompt'],
    'formula': (q['formula'] as String).isEmpty ? null : q['formula'],
    'hints': (q['trigger'] as String).isEmpty ? <String>[] : [q['trigger']],
    'steps':
        (q['answer'] as String).isEmpty && (q['answerPhoto'] as String).isEmpty
        ? <Json>[]
        : [
            {'text': q['answer']},
          ],
    'concepts': <Json>[],
    'variants': <Json>[],
    'blue': {
      for (final key in ['trigger', 'action', 'conditions', 'pitfall'])
        key: (q[key] as String).isEmpty ? '尚未整理，可在编辑题目中补充。' : q[key],
    },
    'source': (q['source'] as String).isEmpty
        ? '用户自行整理；题解尚未经过平台审核。'
        : '${q['source']}\n用户自行整理；题解尚未经过平台审核。',
    'custom': true,
  });
}

String encodeQuestionPackage(
  String id,
  Json question, {
  required bool consent,
  required String author,
}) {
  if (!consent) throw const FormatException('请先确认同意分享这道题');
  if (!RegExp(r'^user-[a-f0-9]{32}$').hasMatch(id)) {
    throw const FormatException('只能分享自己的题目副本');
  }
  if (author.trim().isEmpty || author.length > 80) {
    throw const FormatException('请填写分享署名（最多 80 字）');
  }
  final q = validateQuestion(question);
  if (q['deleted'] == true) throw const FormatException('已删除的题目不能分享');
  // Learning history, private notes and sync credentials are never included.
  return jsonEncode({
    'format': 'blue-note-question',
    'version': 1,
    'id': id,
    'author': author.trim(),
    'question': {...q, 'origin': ''},
  });
}

Json decodeQuestionPackage(String raw) {
  if (utf8.encode(raw).length > 10 * 1024 * 1024) {
    throw const FormatException('题目包超过 10MB');
  }
  final value = jsonDecode(raw);
  if (value is! Json ||
      value['format'] != 'blue-note-question' ||
      value['version'] != 1 ||
      value['id'] is! String ||
      !RegExp(r'^user-[a-f0-9]{32}$').hasMatch(value['id'] as String) ||
      value['author'] is! String ||
      (value['author'] as String).trim().isEmpty ||
      (value['author'] as String).length > 80) {
    throw const FormatException('不是有效的蓝笔题目包');
  }
  final q = validateQuestion(value['question']);
  if (q['deleted'] == true) throw const FormatException('不能导入已删除的题目');
  return {...value, 'question': q};
}

/// These are search candidates from reviewed examples, not an inferred solution.
List<Lesson> suggestLessons(String text, Iterable<Lesson> lessons) {
  final compact = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return [];
  const triggers = <String, List<String>>{
    'math-symmetry': ['sin', 'cos'],
    'math-lagrange': ['中值定理'],
    'net-fragments': ['片偏移'],
    'ds-reverse': ['链表', '反转'],
    'ds-queue': ['队列'],
    'net-http': ['http'],
  };
  return lessons
      .where((lesson) {
        if (lesson.data['custom'] == true) return false;
        if (lesson.concepts.any(
          (c) => compact.contains(
            (c['title'] as String).toLowerCase().replaceAll(RegExp(r'\s+'), ''),
          ),
        )) {
          return true;
        }
        final words = triggers[lesson.id];
        return words != null && words.every(compact.contains);
      })
      .take(4)
      .toList();
}
