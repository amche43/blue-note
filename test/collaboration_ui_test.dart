import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/public_notebook.dart';
import 'package:blue_note/collaboration_pages.dart';
import 'package:blue_note/account_page.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/brand.dart';

class FixtureClient extends CommunityClient {
  FixtureClient() : super({});
  bool accepted = false;
  int sends = 0;
  String sentBody = "";
  final book = <String, dynamic>{
    'id': 'book-${'1' * 32}',
    'title': '高数极限错题本',
    'name': '预览同学',
    'subjects': '高等数学',
    'kind': 'question',
    'saved': 0,
    'liked': 0,
  };
  Json get entry => {
    'id': '2' * 32,
    'mine': false,
    'liked': false,
    'likes': 0,
    'package': {
      'author': '预览同学',
      'question': {
        'title': '泰勒展开中的阶数选择',
        'notebookTitle': '高数极限错题本',
        'questionNumber': '7',
        'contentKind': 'question',
        'prompt': '求下列极限',
        'formula': r'\lim_{x\to0}\frac{\sin x-x}{x^3}',
        'firstThought': '先观察分子抵消后的最低阶项。',
        'errorReason': '只展开到一阶，忽略了下一项。',
        'answer': '将 sin x 展开至三阶，再约去共同的三次方。',
        'action': '注意分母阶数与分子抵消。',
      },
    },
  };
  @override
  Future<Json> request(String method, String path, [Json? data]) async {
    if(path.startsWith('/v1/profiles/'))return {'id':'a'*32,'name':'预览同学','avatar':0,'counts':{'first':10},'specials':[]};
    if (path.endsWith('/workspace')) {
      return {
        ...book,
        'owner': true,
        'ownerId': 'a'*32,
        'member': true,
        'members': [
          {'name': '预览同学'},
        ],
        'application': '',
        'description': '记录极限中的错误思路、关键突破与适用条件。',
        'version': 0,
        'history': [],
      };
    }
    if (path == '/v1/inbox') {
      return {
        'applications': [
          {
            'id': '3' * 32,
            'book': book['id'],
            'title': book['title'],
            'name': '柠檬同学',
            'reason': '我想一起检查展开阶数与使用条件。',
            'canReview': 1,
            'status': accepted ? 'accepted' : 'pending',
          },
        ],
        'rooms': [book],
        'improvements': [{'id':'proposal-test','book':book['id'],'title':book['title'],'entryTitle':'补充极限适用条件','name':'柠檬同学','canReview':1,'status':'pending'}],
      };
    }
    if (path.endsWith('/applications')) {
      accepted = true;
      return {'status': 'accepted'};
    }
    if (path.endsWith('/messages')) {
      if (method == 'POST') {
        sends++;
        sentBody = data!['body'] as String;
      }
      return {
        'items': [
          {
            'id': '4' * 32,
            'name': '柠檬同学',
            'mine': 0,
            'avatar': 11,
            'created': 1789272000000000000,
            'body': '第7题的三阶项，我们再一起核对一下。\n[蓝笔表情:思考]',
          },
          if (sentBody.isNotEmpty)
            {
              'id': '5' * 32,
              'name': '我',
              'avatar': 13,
              'mine': 1,
              'created': 1789272000000000001,
              'body': sentBody,
            },
        ],
      };
    }
    if (path.endsWith('/comments')) return {'items': []};
    if (path.startsWith('/v1/questions/')) return entry;
    return {
      'items': [entry],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'Notebook layers, approvals, chat and account pages work at phone sizes',
    (tester) async {
      await tester.runAsync(() async {
        for (final font in {
          'Roboto': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons':
              '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final f = File(font.value);
          if (await f.exists()) {
            await (FontLoader(font.key)..addFont(
                  Future.value(ByteData.sublistView(await f.readAsBytes())),
                ))
                .load();
          }
        }
      });
      await tester.runAsync(() async {
        for (final family in ['Main', 'Math', 'Size1']) {
          final style = family == 'Math' ? 'Italic' : 'Regular';
          await (FontLoader(
                'packages/flutter_math_fork/KaTeX_$family',
              )..addFont(
                rootBundle.load(
                  'packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_$family-$style.ttf',
                ),
              ))
              .load();
        }
      });
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
      final client = FixtureClient();
      final key = GlobalKey();
      Future<void> show(Widget page) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: blueNoteTheme(),
              home: Scaffold(body: page),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final img =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../ui09-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await show(
        PublicNotebookPage(store: store, client: client, book: client.book),
      );
      await tester.runAsync(() async {
        for (final asset in ['ui-reference', 'launcher']) {
          await precacheImage(
            AssetImage('assets/brand/$asset.png'),
            key.currentContext!,
          );
        }
      });
      await shot('notebook');
      await tester.tap(find.widgetWithText(TextButton,'预览同学'));
      await tester.pumpAndSettle();
      expect(find.text('开放学习履历'),findsOneWidget);
      expect(find.text('初次记录'),findsOneWidget);
      Navigator.of(tester.element(find.text('开放学习履历'))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('未分章'));
      await tester.tap(find.text('未分章'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('泰勒展开中的阶数选择'));
      await tester.tap(find.text('泰勒展开中的阶数选择'));
      await tester.pumpAndSettle();
      await shot('entry');
      await show(CollaborationInbox(store: store, client: client));
      await shot('inbox');
      await tester.tap(find.text('改进'));
      await tester.pumpAndSettle();
      expect(find.text('补充极限适用条件'), findsOneWidget);
      expect(find.text('学习本协作聊天'), findsNothing);
      await shot('improvement-inbox');
      await tester.tap(find.text('协作申请'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同意共同维护'));
      await tester.pumpAndSettle();
      expect(find.text('已同意'), findsOneWidget);
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高数极限错题本'));
      await tester.pumpAndSettle();
      await shot('chat');
      await tester.enterText(find.byType(TextField), '我们一起核对');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(client.sends, 1);
      await tester.tap(find.byTooltip('蓝笔表情'));
      await tester.pumpAndSettle();
      await shot('sticker-picker');
      await tester.tap(find.byKey(const ValueKey('sticker-choice-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(client.sentBody, '[蓝笔表情:加油]');
      expect(find.byType(BlueMessageBody), findsWidgets);
      await shot('chat-sticker');
      await show(AccountPage(store: store));
      await shot('login');
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('选择头像'));
      await tester.tap(find.text('选择头像'));
      await tester.pumpAndSettle();
      await shot('avatar-picker');
      await tester.tap(find.byKey(const ValueKey('avatar-choice-3')));
      await tester.pumpAndSettle();
      expect(find.text('靛蓝'), findsOneWidget);
      await shot('register');
      tester.view.physicalSize = const Size(320, 740);
      for (final page in [
        AccountPage(store: store),
        PublicNotebookPage(store: store, client: client, book: client.book),
        CollaborationInbox(store: store, client: client),
        BookChatPage(
          client: client,
          book: client.book['id'] as String,
          title: '协作聊天',
        ),
      ]) {
        await show(page);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      store.dispose();
    },
  );
}
