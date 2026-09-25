import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'domain.dart';
import 'store.dart';
import 'questions.dart';
import 'learning_fields.dart';

extension AdoptionStore on StudyStore {
  List<Json> adoptionHistory(String book) =>
      settings.entries
          .where((e) => e.key.startsWith('adoption:'))
          .map((e) => jsonDecode(e.value) as Json)
          .where((e) => (e['before'] as Json)['notebookId'] == book)
          .toList()
        ..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));

  Future<void> adoptFields({
    required String lesson,
    required Json expected,
    required Json incoming,
    required Set<String> fields,
  }) async {
    if (fields.isEmpty || fields.any((k) => !comparisonFields.containsKey(k))) {
      throw const FormatException('请选择要采纳的内容');
    }
    final book = expected['notebookId'] as String;
    final raw = settings['fork:$book'];
    if (raw == null || (expected['origin'] as String).isEmpty) {
      throw const FormatException('没有可核对的派生来源');
    }
    final selected = fields.where((k) => expected[k] != incoming[k]).toList();
    if (selected.isEmpty) throw const FormatException('选中的内容已与原作一致');
    final after = validateQuestion({
      ...expected,
      for (final k in selected) k: incoming[k],
    });
    final id = newId();
    await db.transaction((tx) async {
      final rows = await tx.query(
        'events',
        where: 'lesson_id=? AND type=?',
        whereArgs: [lesson, 'question'],
        orderBy: 'at DESC,id DESC',
        limit: 1,
      );
      if (rows.isEmpty ||
          !mapEquals(
            jsonDecode(rows.single['payload'] as String) as Json,
            expected,
          ) ||
          expected['deleted'] == true) {
        throw const FormatException('自己的版本已变动，请重新打开对照页后再选择');
      }
      final now = DateTime.now().millisecondsSinceEpoch,
          previous = rows.single['at'] as int;
      final at = now > previous ? now : previous + 1, eventId = newId();
      await tx.insert('events', {
        'id': eventId,
        'lesson_id': lesson,
        'type': 'question',
        'at': at,
        'payload': jsonEncode(after),
      });
      await tx.insert('settings', {
        'key': 'adoption:$id',
        'value': jsonEncode({
          'id': id,
          'lesson': lesson,
          'source': (jsonDecode(raw) as Json)['source'],
          'origin': expected['origin'],
          'at': at,
          'eventId': eventId,
          'fields': selected,
          'before': expected,
          'after': after,
        }),
      });
    });
    await refresh();
  }

  Future<void> undoAdoption(String id) async {
    await db.transaction((tx) async {
      if ((await tx.query(
        'settings',
        where: 'key=?',
        whereArgs: ['adoptionUndo:$id'],
      )).isNotEmpty) {
        throw const FormatException('这次采纳已经撤销');
      }
      final saved = await tx.query(
        'settings',
        where: 'key=?',
        whereArgs: ['adoption:$id'],
      );
      if (saved.isEmpty) throw const FormatException('找不到采纳记录');
      final record = jsonDecode(saved.single['value'] as String) as Json;
      final rows = await tx.query(
        'events',
        where: 'lesson_id=? AND type=?',
        whereArgs: [record['lesson'], 'question'],
        orderBy: 'at DESC,id DESC',
      );
      if (rows.isEmpty) throw const FormatException('条目已不存在');
      final current = jsonDecode(rows.first['payload'] as String) as Json;
      final fields = (record['fields'] as List).cast<String>(),
          after = record['after'] as Json,
          before = record['before'] as Json;
      if (current['deleted'] == true ||
          current['notebookId'] != before['notebookId'] ||
          current['origin'] != record['origin']) {
        throw const FormatException('条目已删除或移到其他笔记本，不能在这里撤销');
      }
      // Reject intervening edits even if the user later restored the same text.
      for (final row in rows) {
        if ((row['at'] as int) < (record['at'] as int)) break;
        final q = jsonDecode(row['payload'] as String) as Json;
        if (fields.any((k) => q[k] != after[k])) {
          throw const FormatException('采纳的字段后来又被修改，请手动对照历史，避免覆盖新内容');
        }
      }
      final restored = validateQuestion({
        ...current,
        for (final k in fields) k: before[k],
      });
      final now = DateTime.now().millisecondsSinceEpoch,
          previous = rows.first['at'] as int;
      final at = now > previous ? now : previous + 1, eventId = newId();
      await tx.insert('events', {
        'id': eventId,
        'lesson_id': record['lesson'],
        'type': 'question',
        'at': at,
        'payload': jsonEncode(restored),
      });
      await tx.insert('settings', {
        'key': 'adoptionUndo:$id',
        'value': jsonEncode({'id': id, 'eventId': eventId, 'at': at}),
      });
    });
    await refresh();
  }
}
