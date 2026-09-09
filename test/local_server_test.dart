import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:blue_note/community.dart';

void main() {
  test('Real Dart client verifies local HTTPS certificate and authenticates', () async {
    final original = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      final config = CommunityClient.parse(await File('server/data/learner-one.json').readAsString());
      config['url'] = 'https://127.0.0.1:8788';
      final client = CommunityClient(config);
      expect((await client.request('GET', '/v1/me'))['name'], 'learner-one');
      expect((await client.request('GET', '/v1/questions'))['items'], isList);
    } finally { HttpOverrides.global = original; }
  }, skip: !const bool.fromEnvironment('BLUE_NOTE_LOCAL_TEST'));
}
