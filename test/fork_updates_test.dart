import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/fork_updates.dart';

class SourceFixture extends CommunityClient {
  final Json snapshot;
  bool fail = false;
  SourceFixture(this.snapshot) : super({});
  @override
  Future<Json> request(String method, String path, [Json? data]) async {
    if (method != 'GET') {
      throw StateError('Comparison must never write to server');
    }
    if (fail) throw const FormatException('后台暂不可用，请重试');
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'Three-way comparison distinguishes new, changed, withdrawn and private edits without writing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final book = 'book-${newId()}', source = 'book-${newId()}';
      Json pack(String id, String title, String answer) => {
        'id': id,
        'author': '原作者',
        'question': {
          ...blankQuestion(),
          'title': title,
          'prompt': '求极限',
          'answer': answer,
        },
      };
      final a = pack('user-${newId()}', '极限与展开', '先展开'),
          b = pack('user-${newId()}', '旧题', '原解法'),
          c = pack('user-${newId()}', '新增知识卡', '比较阶数');
      final baseline = <String, dynamic>{
        'title': '高数极限错题本',
        'source': source,
        'items': [a, b],
      };
      await s.createFork(book, baseline);
      final local = s.questions.entries
          .firstWhere((e) => e.value['origin'] == a['id'])
          .key;
      await s.saveQuestion({
        ...s.questions[local]!,
        'answer': '我先判断极限形式',
      }, id: local);
      final latest = <String, dynamic>{
        'title': '高数极限错题本',
        'source': source,
        'items': [
          {
            ...a,
            'question': {...a['question'] as Json, 'answer': '展开至三阶并验证余项'},
          },
          c,
        ],
      };
      final changes = compareFork(s, book, baseline, latest);
      expect(changes.map((r) => r.status), ['原作已修改', '原作已撤回', '原作新增']);
      expect(changes.first.mineChanged, isTrue);
      final eventCount = s.events.length;
      final fixture = SourceFixture(latest);
      final key = GlobalKey();
      await tester.runAsync(() async {
        for (final item in [
          ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
          (
            'MaterialIcons',
            '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          final bytes = await File(item.$2).readAsBytes();
          await (FontLoader(
            item.$1,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: blueNoteTheme(),
            home: ForkUpdatesPage(store: s, book: book, client: fixture),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('新增 1 · 修改 1 · 撤回 1'), findsOneWidget);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../ui15-source-updates.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('极限与展开'));
      await tester.pumpAndSettle();
      expect(find.text('先展开'), findsOneWidget);
      expect(find.text('展开至三阶并验证余项'), findsOneWidget);
      expect(find.text('我先判断极限形式'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(s.events.length, eventCount);
      expect(s.questions.length, 2);
      Navigator.of(tester.element(find.text('先展开'))).pop();
      await tester.pumpAndSettle();
      fixture.fail = true;
      await tester.tap(find.byTooltip('检查原作更新'));
      await tester.pumpAndSettle();
      expect(find.text('后台暂不可用，请重试'), findsOneWidget);
      expect(s.events.length, eventCount);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
