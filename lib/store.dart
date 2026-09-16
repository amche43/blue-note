import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'domain.dart';
import 'questions.dart';
import 'full_backup.dart';

class StudyStore extends ChangeNotifier {
  final Database db;
  final List<Lesson> bundledLessons;
  List<Lesson> lessons = [];
  Map<String, Json> questions = {};
  List<StudyEvent> events = [];
  Map<String, String> settings = {};
  StudyStore(this.db, this.bundledLessons);

  static Future<StudyStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final selected = factory ?? databaseFactory;
    final location =
        path ??
        paths.join(await selected.getDatabasesPath(), 'blue_note_v1.db');
    final db = await selected.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL, type TEXT NOT NULL, at INTEGER NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX events_lesson ON events (lesson_id, at)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final data =
        jsonDecode(await rootBundle.loadString('assets/lessons.json')) as Json;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS capture_records (lesson_id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    final store = StudyStore(
      db,
      (data['lessons'] as List).map((e) => Lesson(e as Json)).toList(),
    );
    await store.refresh();
    return store;
  }

  Future<void> refresh() async {
    events = (await db.query('events'))
        .map(
          (row) => StudyEvent(
            id: row['id'] as String,
            lessonId: row['lesson_id'] as String,
            type: row['type'] as String,
            at: row['at'] as int,
            payload: jsonDecode(row['payload'] as String) as Json,
          ),
        )
        .toList();
    settings = {
      for (final row in await db.query('settings'))
        row['key'] as String: row['value'] as String,
    };
    questions = {};
    final revisions = events.where((e) => e.type == 'question').toList()
      ..sort(compareEvents);
    for (final event in revisions) {
      questions[event.lessonId] = event.payload;
    }
    lessons = [
      ...bundledLessons,
      ...questions.entries
          .where((e) => e.value['deleted'] == false)
          .map((e) => questionLesson(e.key, e.value)),
    ];
    notifyListeners();
  }

  Progress progress(String id) =>
      Progress.fromEvents(events.where((e) => e.lessonId == id));
  List<Lesson> get due =>
      lessons.where((l) {
          final at = progress(l.id).due;
          return at != null && !at.isAfter(DateTime.now());
        }).toList()
        ..sort((a, b) => progress(a.id).due!.compareTo(progress(b.id).due!));
  bool get guided => settings['mode'] != 'challenge';

  Future<void> setting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await refresh();
  }

  Future<void> merge(
    Iterable<StudyEvent> incoming, {
    Map<String, String> captures = const {},
    Map<String, String> localSettings = const {},
    bool keepExistingCaptures = false,
    List<String> removeSettings = const [],
    Map<String, Json> expectedQuestions = const {},
  }) async {
    final validated = incoming
        .map((event) => StudyEvent.fromJson(event.toJson()))
        .toList();
    await db.transaction((tx) async {
      for (final e in expectedQuestions.entries) {
        final rows = await tx.query(
          'events',
          where: 'lesson_id=? AND type=?',
          whereArgs: [e.key, 'question'],
          orderBy: 'at DESC,id DESC',
          limit: 1,
        );
        if (rows.isEmpty ||
            !mapEquals(
              jsonDecode(rows.first['payload'] as String) as Json,
              e.value,
            )) {
          throw const FormatException('原条目已变动，请重新核对或另存为新条目');
        }
      }
      for (final key in removeSettings) {
        await tx.delete('settings', where: 'key=?', whereArgs: [key]);
      }
      for (final capture in captures.entries) {
        await tx.insert(
          'capture_records',
          {'lesson_id': capture.key, 'data': capture.value},
          conflictAlgorithm: keepExistingCaptures
              ? ConflictAlgorithm.ignore
              : ConflictAlgorithm.replace,
        );
      }
      for (final entry in localSettings.entries) {
        await tx.insert('settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final e in validated) {
        final existing = await tx.query(
          'events',
          where: 'id = ?',
          whereArgs: [e.id],
        );
        final encoded = jsonEncode(e.payload);
        if (existing.isNotEmpty) {
          final old = existing.single;
          if (old['lesson_id'] != e.lessonId ||
              old['type'] != e.type ||
              old['at'] != e.at ||
              !mapEquals(
                jsonDecode(old['payload'] as String) as Json,
                e.payload,
              )) {
            throw const FormatException('同一记录编号包含不同内容，已停止导入');
          }
          continue;
        }
        await tx.insert('events', {
          'id': e.id,
          'lesson_id': e.lessonId,
          'type': e.type,
          'at': e.at,
          'payload': encoded,
        });
      }
    });
    await refresh();
  }

  Future<void> note(String lessonId, String text) => merge([
    StudyEvent(
      id: newId(),
      lessonId: lessonId,
      type: 'note',
      at: DateTime.now().millisecondsSinceEpoch,
      payload: {'text': text.trim()},
    ),
  ]);

  Future<void> attempt(
    String lessonId, {
    required String variantId,
    required String rating,
    required bool assisted,
    required bool correct,
    required String reason,
  }) => merge([
    StudyEvent(
      id: newId(),
      lessonId: lessonId,
      type: 'attempt',
      at: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'variantId': variantId,
        'rating': rating,
        'assisted': assisted,
        'correct': correct,
        'reason': reason,
      },
    ),
  ]);

  String backup() => encodeBackup(events);

  Future<void> createFork(String bookId, Json snapshot) async {
    if (settings.containsKey('notebook:$bookId')) return;
    final packages = (snapshot['items'] as List).cast<Json>();
    final title = '${snapshot['title']} · 我的版本';
    final label = title.substring(0, title.length.clamp(0, 80));
    final revisions = <StudyEvent>[];
    for (var i = 0; i < packages.length; i++) {
      final p = packages[i];
      final attribution =
          '基于 ${p['author'] ?? '学习者'} 的《${snapshot['title']}》 · ${snapshot['source']}\n${(p['question'] as Json)['source'] ?? ''}';
      final q = validateQuestion({
        ...p['question'] as Json,
        'notebookId': bookId,
        'notebookTitle': label,
        'questionNumber': '${i + 1}',
        'origin': p['id'],
        'source': attribution.substring(0, attribution.length.clamp(0, 1000)),
      });
      revisions.add(
        StudyEvent(
          id: newId(),
          lessonId: 'user-${newId()}',
          type: 'question',
          at: DateTime.now().millisecondsSinceEpoch,
          payload: q,
        ),
      );
    }
    final knowledge = revisions.every(
      (r) => r.payload['contentKind'] == 'knowledge',
    );
    await merge(
      revisions,
      localSettings: {
        'notebook:$bookId': jsonEncode({
          'title': label,
          'kind': knowledge ? 'knowledge' : 'question',
        }),
        'fork:$bookId': jsonEncode(snapshot),
      },
    );
  }

  Future<String> fullBackup() async {
    final data = await db.transaction(
      (tx) async => {
        'format': 'blue-note-full',
        'version': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'events': (await tx.query('events'))
            .map(
              (r) => {
                'id': r['id'],
                'lessonId': r['lesson_id'],
                'type': r['type'],
                'at': r['at'],
                'payload': jsonDecode(r['payload'] as String),
              },
            )
            .toList(),
        'settings': {
          for (final r in await tx.query('settings'))
            if (portableSetting(r['key'] as String))
              r['key'] as String: r['value'] as String,
        },
        'captures': {
          for (final r in await tx.query('capture_records'))
            r['lesson_id'] as String: r['data'] as String,
        },
      },
    );
    final raw = jsonEncode(data);
    FullBackup.decode(raw);
    return raw;
  }

  Future<int> restoreFull(String raw) async {
    final input = FullBackup.decode(raw);
    final before = events.length;
    await merge(
      input.events,
      captures: input.captures,
      localSettings: input.settings,
      keepExistingCaptures: true,
    );
    return events.length - before;
  }

  Future<String> saveQuestion(
    Json input, {
    String? id,
    Json? capture,
    String? clearDraftKey,
    Json? expected,
  }) async {
    final prepared = {...input};
    final book = prepared['notebookId'] as String? ?? '';
    if (book.isNotEmpty && (prepared['questionNumber'] ?? '') == '') {
      final maxNumber = questions.values
          .where((q) => q['notebookId'] == book)
          .fold<int>(0, (n, q) {
            final v = int.tryParse(q['questionNumber'] as String? ?? '') ?? 0;
            return n > v ? n : v;
          });
      prepared['questionNumber'] = '${maxNumber + 1}';
    }
    final data = validateQuestion(prepared);
    final key = id ?? 'user-${newId()}';
    if (id != null && !questions.containsKey(id)) {
      throw const FormatException('找不到可编辑的题目');
    }
    final latest = events
        .where((e) => e.lessonId == key)
        .fold<int>(0, (value, e) => e.at > value ? e.at : value);
    final now = DateTime.now().millisecondsSinceEpoch;
    await merge(
      [
        StudyEvent(
          id: newId(),
          lessonId: key,
          type: 'question',
          at: now > latest ? now : latest + 1,
          payload: data,
        ),
      ],
      captures: capture == null
          ? const {}
          : {
              key: jsonEncode({...capture, 'user_confirmed': data}),
            },
      removeSettings: clearDraftKey == null ? const [] : [clearDraftKey],
      expectedQuestions: expected == null ? const {} : {key: expected},
    );
    return key;
  }

  Future<void> deleteQuestion(String id, {String? clearDraftKey}) async {
    final question = questions[id];
    if (question == null) throw const FormatException('题目不存在');
    await saveQuestion(
      {...question, 'deleted': true},
      id: id,
      clearDraftKey: clearDraftKey,
    );
  }

  Future<String> importQuestionPackage(String raw) async {
    final package = decodeQuestionPackage(raw);
    final incoming = package['question'] as Json;
    final existing = questions.entries
        .where(
          (e) =>
              e.value['deleted'] == false &&
              (e.value['origin'] == package['id'] ||
                  ((incoming['notebookId'] as String).isNotEmpty &&
                      e.value['notebookId'] == incoming['notebookId'] &&
                      e.value['questionNumber'] == incoming['questionNumber'])),
        )
        .firstOrNull;
    if (existing != null) {
      return existing.key; // Never overwrite a reader's own edits.
    }
    final data = package['question'] as Json;
    final source = '分享者：${package['author']}\n${data['source']}';
    return saveQuestion({
      ...data,
      'origin': package['id'],
      'source': source.substring(0, source.length.clamp(0, 1000)),
    });
  }

  Future<int> restore(String raw) async {
    final input = decodeBackup(
      raw,
    ); // Validate the entire file before the transaction.
    final count = events.length;
    await merge(input);
    return events.length - count;
  }

  Future<int> sync(String address, String token) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入完整的服务地址');
    }
    if (uri.scheme != 'https') {
      throw const FormatException('同步需要 HTTPS 地址与有效证书');
    }
    if (token.trim().length < 32) throw const FormatException('同步口令至少 32 个字符');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(uri.replace(path: '/v1/sync'))
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${token.trim()}',
      );
      request.headers.contentType = ContentType.json;
      request.write(backup());
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          response.statusCode == 401
              ? '同步口令不正确'
              : '服务暂不可用（${response.statusCode}）',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('同步数据超出首版上限');
        }
      }
      final added = await restore(utf8.decode(bytes));
      await setting('syncUrl', address.trim());
      await setting('lastSync', DateTime.now().toIso8601String());
      return added;
    } finally {
      client.close(force: true);
    }
  }
}
