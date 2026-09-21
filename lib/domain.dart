import 'dart:convert';
import 'dart:math';
import 'questions.dart';

typedef Json = Map<String, dynamic>;

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Lesson {
  final Json data;
  Lesson(this.data);
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  String get subject => data['subject'] as String;
  String get chapter => data['chapter'] as String;
  String get prompt => data['prompt'] as String;
  String? get formula => data['formula'] as String?;
  List<String> get hints => List<String>.from(data['hints'] as List);
  List<Json> get steps => (data['steps'] as List).cast<Json>();
  List<Json> get concepts => (data['concepts'] as List).cast<Json>();
  List<Json> get variants => (data['variants'] as List).cast<Json>();
  Json get blue => data['blue'] as Json;
}

class StudyEvent {
  final String id, lessonId, type;
  final int at;
  final Json payload;
  StudyEvent({
    required this.id,
    required this.lessonId,
    required this.type,
    required this.at,
    required this.payload,
  });
  Json toJson() => {
    'id': id,
    'lessonId': lessonId,
    'type': type,
    'at': at,
    'payload': payload,
  };
  factory StudyEvent.fromJson(Json json) {
    final id = json['id'],
        lesson = json['lessonId'],
        type = json['type'],
        at = json['at'],
        payload = json['payload'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        lesson is! String ||
        !RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(lesson) ||
        !['note', 'attempt', 'question'].contains(type) ||
        at is! int ||
        at < 0 ||
        at >
            DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch ||
        payload is! Json) {
      throw const FormatException('学习记录格式不正确');
    }
    if (type == 'question') {
      if (!lesson.startsWith('user-') ||
          !RegExp(r'^user-[a-f0-9]{32}$').hasMatch(lesson)) {
        throw const FormatException('自建题目编号不正确');
      }
      validateQuestion(payload);
    } else if (type == 'note') {
      if (payload['text'] is! String ||
          (payload['text'] as String).length > 20000) {
        throw const FormatException('笔记格式不正确或过长');
      }
    } else {
      if (!['again', 'hard', 'good'].contains(payload['rating']) ||
          payload['assisted'] is! bool ||
          payload['variantId'] is! String ||
          payload['correct'] is! bool ||
          payload['reason'] is! String) {
        throw const FormatException('作答记录格式不正确');
      }
    }
    return StudyEvent(
      id: id,
      lessonId: lesson,
      type: type as String,
      at: at,
      payload: payload,
    );
  }
}

/// One portable format for Android, future iOS, manual backups and the server.
List<StudyEvent> decodeBackup(String raw) {
  if (utf8.encode(raw).length > 8 * 1024 * 1024) {
    throw const FormatException('备份超过 8MB');
  }
  final data = jsonDecode(raw);
  if (data is! Json ||
      ![1, 2].contains(data['schemaVersion']) ||
      data['events'] is! List) {
    throw const FormatException('不是支持的蓝笔备份');
  }
  final events = data['events'] as List;
  if (events.length > 20000) throw const FormatException('记录数量超出首版上限');
  return events.map((e) {
    if (e is! Json) throw const FormatException('记录格式不正确');
    final event = StudyEvent.fromJson(e);
    if (data['schemaVersion'] == 1 && event.type == 'question') {
      throw const FormatException('自建题目需要 v2 备份格式');
    }
    return event;
  }).toList();
}

String encodeBackup(Iterable<StudyEvent> events) => jsonEncode({
  'schemaVersion': events.any((e) => e.type == 'question') ? 2 : 1,
  'events': events.map((e) => e.toJson()).toList(),
});

/// Event ordering is deterministic across devices. All note revisions remain in
/// the journal even when a later revision is the visible one.
int compareEvents(StudyEvent a, StudyEvent b) {
  final time = a.at.compareTo(b.at);
  return time != 0 ? time : a.id.compareTo(b.id);
}

class Progress {
  String? note;
  DateTime? due;
  int independent = 0, attempts = 0;
  String status = '未学习';
  final List<StudyEvent> noteHistory = [];
  Progress.fromEvents(Iterable<StudyEvent> input) {
    final events = input.toList()..sort(compareEvents);
    int? lastCredit;
    for (final event in events) {
      if (event.type == 'question') continue;
      if (event.type == 'note') {
        note = event.payload['text'] as String;
        noteHistory.add(event);
        continue;
      }
      attempts++;
      final p = event.payload;
      final rating = p['rating'];
      final passed =
          p['correct'] == true && p['assisted'] == false && rating == 'good';
      if (passed) {
        if (lastCredit == null ||
            event.at - lastCredit >= const Duration(hours: 24).inMilliseconds) {
          independent++;
          lastCredit = event.at;
          status = '独立验证 $independent 次';
        } else {
          status = '本轮答对 · 待隔后验证';
        }
      } else {
        independent = 0;
        lastCredit = null;
        status = rating == 'again' || p['correct'] != true ? '需要再练' : '借助提示完成';
      }
      // Explicit conservative v1 schedule, not an implementation of FSRS.
      final delay = rating == 'again' || p['correct'] != true
          ? const Duration(minutes: 10)
          : !passed
          ? const Duration(days: 1)
          : Duration(days: [1, 3, 7, 14, 30][min(independent - 1, 4)]);
      due = DateTime.fromMillisecondsSinceEpoch(
        passed ? lastCredit! : event.at,
      ).add(delay);
    }
  }
}
