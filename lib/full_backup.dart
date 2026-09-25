import 'dart:convert';
import 'domain.dart';
import 'questions.dart';
import 'learning_fields.dart';

const fullBackupLimit = 64 * 1024 * 1024;
bool portableSetting(String key) =>
    key.startsWith('notebook:') ||
    key.startsWith('order:') ||
    key.startsWith('color:') ||
    key.startsWith('studyTime:') ||
    key.startsWith('favorite:') ||
    key.startsWith('fork:') ||
    key.startsWith('adoption:') ||
    key.startsWith('adoptionUndo:') ||
    ['mode', 'lastOpenedLesson'].contains(key);

class FullBackup {
  final List<StudyEvent> events;
  final Map<String, String> settings, captures;
  FullBackup(this.events, this.settings, this.captures);
  String get summary =>
      '${events.length} 条学习记录 · ${settings.keys.where((k) => k.startsWith('notebook:')).length} 个笔记本设置 · ${captures.length} 份图片与识别记录';
  static FullBackup decode(String raw) {
    if (utf8.encode(raw).length > fullBackupLimit) {
      throw const FormatException('备份超过 64MB，请减少图片后再试');
    }
    final data = jsonDecode(raw);
    if (data is! Json ||
        data['format'] != 'blue-note-full' ||
        data['version'] != 1 ||
        data['events'] is! List ||
        data['settings'] is! Json ||
        data['captures'] is! Json) {
      throw const FormatException('不是支持的完整学习备份');
    }
    final source = data['events'] as List;
    if (source.length > 20000) throw const FormatException('学习记录超过 20000 条');
    final events = source.map((e) => StudyEvent.fromJson(e as Json)).toList();
    final settings = Map<String, String>.from(data['settings'] as Json);
    for (final e in settings.entries) {
      if (!portableSetting(e.key) ||
          e.value.length >
              (e.key.startsWith('fork:')
                  ? 16 * 1024 * 1024
                  : e.key.startsWith('adoption:')
                  ? 256 * 1024
                  : 20000)) {
        throw const FormatException('备份含不支持的设置');
      }
      if (e.key.startsWith('adoption:') || e.key.startsWith('adoptionUndo:')) {
        final r = jsonDecode(e.value);
        if (r is! Json ||
            r['id'] != e.key.split(':').last ||
            r['eventId'] is! String ||
            r['at'] is! int ||
            !events.any(
              (ev) =>
                  ev.id == r['eventId'] &&
                  ev.type == 'question' &&
                  ev.at == r['at'],
            )) {
          throw const FormatException('采纳历史缺少对应修改记录');
        }
        if (e.key.startsWith('adoption:')) {
          final before = validateQuestion(r['before']),
              after = validateQuestion(r['after']);
          if (r['lesson'] is! String ||
              r['fields'] is! List ||
              (r['fields'] as List).isEmpty ||
              (r['fields'] as List).any(
                (k) => !comparisonFields.containsKey(k),
              ) ||
              r['origin'] != before['origin'] ||
              before['notebookId'] != after['notebookId'] ||
              before['origin'] != after['origin'] ||
              r['source'] is! String) {
            throw const FormatException('采纳历史格式无效');
          }
          final event = events.firstWhere((ev) => ev.id == r['eventId']);
          final recorded = validateQuestion(event.payload);
          if (event.lessonId != r['lesson'] ||
              questionLimits.keys.any((k) => recorded[k] != after[k])) {
            throw const FormatException('采纳历史与修改记录不一致');
          }
        } else if (!settings.containsKey('adoption:${r['id']}')) {
          throw const FormatException('撤销记录缺少采纳历史');
        }
      } else if (e.key.startsWith('fork:')) {
        final fork = jsonDecode(e.value);
        if (fork is! Json ||
            fork['source'] is! String ||
            fork['items'] is! List) {
          throw const FormatException('派生来源无效');
        }
        for (final p in fork['items'] as List) {
          if (p is! Json || p['question'] is! Json) {
            throw const FormatException('派生条目无效');
          }
          validateQuestion(p['question'] as Json);
        }
      } else if (e.key.startsWith('color:') || e.key.startsWith('studyTime:')) {
        final n = int.tryParse(e.value);
        if (n == null ||
            n < 0 ||
            n > (e.key.startsWith('color:') ? 5 : 86400)) {
          throw const FormatException('显示或学习时长数据无效');
        }
      } else if (e.key.startsWith('order:')) {
        final ids = jsonDecode(e.value);
        if (ids is! List ||
            ids.length > 20000 ||
            ids.any((v) => v is! String || v.length > 300)) {
          throw const FormatException('排序数据无效');
        }
      } else if (e.key.startsWith('notebook:')) {
        final b = jsonDecode(e.value);
        if (e.key.length <= 9 ||
            b is! Json ||
            b['title'] is! String ||
            (b['title'] as String).trim().isEmpty ||
            !['knowledge', 'question'].contains(b['kind']) ||
            (b['chapters'] != null &&
                (b['chapters'] is! List ||
                    (b['chapters'] as List).length > 300 ||
                    (b['chapters'] as List).any(
                      (c) => c is! String || c.trim().isEmpty || c.length > 120,
                    )))) {
          throw const FormatException('笔记本设置无效');
        }
      } else if (e.key.startsWith('favorite:') &&
          !['true', 'false'].contains(e.value)) {
        throw const FormatException('收藏设置无效');
      }
    }
    final captures = Map<String, String>.from(data['captures'] as Json);
    final questionIds = events
        .where((e) => e.type == 'question')
        .map((e) => e.lessonId)
        .toSet();
    for (final e in captures.entries) {
      if (!questionIds.contains(e.key)) {
        throw const FormatException('图片没有对应学习条目');
      }
      final capture = jsonDecode(e.value);
      if (capture is! Json) throw const FormatException('图片记录格式无效');
      final image = capture['source_image'];
      if (image != null) {
        if (image is! String || image.length > 16 * 1024 * 1024) {
          throw const FormatException('单张图片过大或无效');
        }
        final bytes = base64Decode(image);
        if (bytes.length < 8 ||
            !((bytes[0] == 255 && bytes[1] == 216) ||
                (bytes[0] == 137 &&
                    bytes[1] == 80 &&
                    bytes[2] == 78 &&
                    bytes[3] == 71))) {
          throw const FormatException('图片格式无效');
        }
      }
    }
    return FullBackup(events, settings, captures);
  }
}
