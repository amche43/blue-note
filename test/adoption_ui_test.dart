import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/adoption_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'User explicitly selects one field, confirms adoption and can undo offline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = await StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      final book = 'book-${newId()}';
      await s.createFork(book, {
        'title': '极限专题',
        'source': 'book-${newId()}',
        'items': [
          {
            'id': 'user-${newId()}',
            'question': {
              ...blankQuestion(),
              'title': '三阶泰勒展开',
              'prompt': '求极限',
              'answer': '直接求导',
              'firstThought': '我容易忘记比较分母阶数',
            },
          },
        ],
      });
      final id = s.questions.keys.single,
          before = {...s.questions.values.single};
      final incoming = {
        ...before,
        'answer': '先判断极限形式，再展开到三阶。',
        'firstThought': '原作者自己的思路',
      };
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
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: blueNoteTheme(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push<bool>(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => AdoptionPage(
                            store: s,
                            lesson: id,
                            before: before,
                            incoming: incoming,
                          ),
                        ),
                      ),
                      child: const Text('开始采纳'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push<void>(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdoptionHistoryPage(store: s, book: book),
                        ),
                      ),
                      child: const Text('查看历史'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始采纳'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '采纳所选 0 项'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('正确解法'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '我的理解'),
            )
            .value,
        isFalse,
      );
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../ui16-selective-adoption.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('采纳所选 1 项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认采纳'));
      await tester.pumpAndSettle();
      expect(s.questions[id]!['answer'], incoming['answer']);
      expect(s.questions[id]!['firstThought'], before['firstThought']);
      await tester.tap(find.text('查看历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('三阶泰勒展开'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('撤销这次采纳'));
      await tester.tap(find.text('撤销这次采纳'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认撤销'));
      await tester.pumpAndSettle();
      expect(s.questions[id]!['answer'], before['answer']);
      expect(find.textContaining('已撤销'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await s.db.close();
      s.dispose();
    },
  );
}
