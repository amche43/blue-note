import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/avatar_page.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';

class AvatarFixture extends CommunityClient {
  AvatarFixture() : super({});
  String image = '', state = '', active = '';
  int submissions = 0;
  @override
  Future<Json> request(String method, String path, [Json? data]) async {
    if (path == '/v1/me') return {'name': '预览同学', 'avatar': 0};
    if (method == 'POST') {
      image = data!['image'] as String;
      state = 'pending';
      submissions++;
      return {'status': state};
    }
    return {
      'activeImage': active,
      'request': state.isEmpty
          ? null
          : {'status': state, 'reason': '', 'image': image},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Avatar crop stays in bounds at both aspect ratios', () {
    expect(
      avatarCropRect(400, 200, 1, -1, 0),
      const Rect.fromLTWH(0, 0, 200, 200),
    );
    expect(
      avatarCropRect(200, 400, 2, 1, 1),
      const Rect.fromLTWH(100, 300, 100, 100),
    );
  });
  testWidgets(
    'Photo upload remains private until approved and defaults are compact',
    (tester) async {
      await tester.runAsync(() async {
        for (final f in {
          'Roboto': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons':
              '../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(f.key)..addFont(
                Future.value(
                  ByteData.sublistView(await File(f.value).readAsBytes()),
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
      final client = AvatarFixture();
      final key = GlobalKey();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('blue_note/photo'),
        (_) async => (await rootBundle.load(
          'assets/brand/app-icon.png',
        )).buffer.asUint8List(),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('blue_note/photo'),
          null,
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: blueNoteTheme(),
            home: AvatarPage(store: store, client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final img in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(img.image, key.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../ui10-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.text('选择默认吉祥物'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('avatar-choice-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('avatar-choice-8')), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('avatar-custom')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.text('调整照片位置'), findsOneWidget);
      await shot('crop');
      await tester.scrollUntilVisible(find.byType(CheckboxListTile), 250);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('提交头像审核'));
      await tester.runAsync(() async {
        await tester.tap(find.text('提交头像审核'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(client.submissions, 1);
      expect(store.settings['avatarImage'], '');
      expect(find.text('照片待审核'), findsOneWidget);
      await shot('pending');
      client.state = 'approved';
      client.active = client.image;
      await tester.tap(find.byTooltip('刷新审核状态'));
      await tester.pumpAndSettle();
      expect(store.settings['avatarImage'], client.image);
      expect(find.text('照片审核已通过'), findsOneWidget);
      await shot('approved');
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      store.dispose();
    },
  );
}
