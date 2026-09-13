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
import 'package:blue_note/community.dart';
import 'package:blue_note/hall.dart';

class PreviewCommunity extends CommunityClient {
  PreviewCommunity() : super({});
  @override
  Future<Json> request(String method, String path, [Json? data]) async => {
    'items': [
      for (var i = 0; i < 3; i++)
        {
          'id': 'book-${'$i' * 32}',
          'title': ['高数极限错题本', '线性代数知识本', '操作系统课程笔记'][i],
          'name': '预览用户',
          'count': [12, 8, 6][i],
          'subjects': ['高等数学', '线性代数', '操作系统'][i],
          'kind': i == 0 ? 'question' : 'knowledge',
          'likes': 0,
          'saves': 0,
          'liked': 0,
          'saved': 0,
        },
    ],
    'nextOffset': null,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('Studio pages render at phone widths and profile changes persist', (
    tester,
  ) async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await tester.runAsync(font.exists) ?? false) {
      await tester.runAsync(() async {
        final b = await font.readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(b)))).load();
      });
    }
    final icons = File(
      '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await tester.runAsync(icons.exists) ?? false) {
      await tester.runAsync(() async {
        final b = await icons.readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(b)))).load();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(
      () => StudyStore.open(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
    ))!;
    for (var i = 0; i < 3; i++) {
      await store.saveQuestion({
        ...blankQuestion(),
        'title': ['极限中的条件检查', '矩阵秩的性质', '进程与线程'][i],
        'subject': ['高等数学', '线性代数', '操作系统'][i],
        'prompt': '仅用于界面测试的内容',
        'contentKind': i == 0 ? 'question' : 'knowledge',
        'notebookId': 'book-${'$i' * 32}',
        'notebookTitle': ['高数极限错题本', '线性代数知识本', '操作系统课程笔记'][i],
      });
    }
    final now = DateTime.now();
    await store.merge([
      for (var day = 0; day < 90; day++)
        if (day % 3 != 0)
          for (var n = 0; n < day % 8 + 1; n++)
            StudyEvent(
              id: newId(),
              lessonId: 'math-symmetry',
              type: 'note',
              at: DateTime(
                now.year,
                now.month,
                now.day - day,
                10,
                n,
              ).millisecondsSinceEpoch,
              payload: {'text': '仅用于截图的测试笔记'},
            ),
    ]);
    final key = GlobalKey();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final img =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../ui07-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: BlueNoteApp(store: store, showWelcome: true),
      ),
    );
    await tester.runAsync(() async {
      for (final asset in ['ui-reference', 'avatars', 'subjects', 'mascots']) {
        await precacheImage(
          AssetImage('assets/brand/$asset.png'),
          key.currentContext!,
        );
      }
    });
    await shot('welcome');
    await tester.ensureVisible(find.text('开始我的学习'));
    await tester.tap(find.text('开始我的学习'));
    await tester.pumpAndSettle();
    expect(store.settings['welcomeSeen'], 'true');
    await shot('home-demo');
    await store.setting('notebook:${'book-${'e' * 32}'}','{"title":"空白学习本","kind":"question"}');
    await tester.tap(find.text('搜索学习本、知识点、题目…'));
    await tester.pumpAndSettle();
    final search=find.byKey(const ValueKey('search-5'));
    await tester.ensureVisible(search);
    await tester.enterText(search,'空白学习本');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile,'空白学习本'),findsOneWidget);
    await tester.pumpWidget(RepaintBoundary(key:key,child:BlueNoteApp(key:UniqueKey(),store:store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await shot('profile-demo');
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '蓝笔同学');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(store.settings['profileName'], '蓝笔同学');
    await tester.tap(find.text('通知').last);
    await tester.pumpAndSettle();
    await shot('notifications');
    await tester.tap(find.byTooltip('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建学习本'));
    await tester.pumpAndSettle();
    await shot('create');
    await tester.enterText(find.byType(TextField), '新建测试知识本');
    await tester.tap(find.text('知识本'));
    await tester.tap(find.text('创建并打开'));
    await tester.pumpAndSettle();
    expect(find.text('新建测试知识本'), findsOneWidget);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: inkBlue),
            scaffoldBackgroundColor: paper,
          ),
          home: HallPage(client: PreviewCommunity(), store: store),
        ),
      ),
    );
    await shot('explore-demo');
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(BlueNoteApp(store: store));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.db.close();
    store.dispose();
  });
}
