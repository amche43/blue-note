import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('Narrow phone layout and actual Flutter preview', (tester) async {
    // Use an installed font only for local preview; no font file is redistributed.
    final font=File('C:/Windows/Fonts/msyh.ttc');
    if(await tester.runAsync(font.exists) ?? false){
      await tester.runAsync(() async {
        final data=await font.readAsBytes();
        await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(data)))).load();
      });
    }
    final icons=File('../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if(await tester.runAsync(icons.exists) ?? false){
      await tester.runAsync(() async {
        final data=await icons.readAsBytes();
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(data)))).load();
      });
    }
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=(await tester.runAsync(() => StudyStore.open(factory:databaseFactoryFfiNoIsolate,path:inMemoryDatabasePath)))!;
    final key=GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key:key,child:BlueNoteApp(store:store)));
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    if(Platform.isWindows){
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:2);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await File('../blue-note-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.physicalSize=const Size(320,740);
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await tester.tap(find.text('学习'));await tester.pumpAndSettle();
    await tester.tap(find.text('添加我的题目'));await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    tester.view.physicalSize=const Size(390,844);
    await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    if(Platform.isWindows){
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:2);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await File('../blue-note-question-editor-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
    await store.db.close();store.dispose();
  });
}
