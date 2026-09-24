import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/learning_profile_page.dart';
class ProfileFixture extends CommunityClient{
 ProfileFixture():super({});
 @override Future<Json> request(String method,String path,[Json? body])async=>{'id':'a'*32,'name':'蓝笔同学','avatar':0,'counts':{'first':52,'open':3,'knowledge':100,'contribution':12,'accepted':10,'momentum':12},'specials':[]};
}
void main(){
 testWidgets('Public learning profile shows tiers, rules and earned-only filter at phone widths',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{final bytes=await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)))).load();});
  await tester.runAsync(()async{final bytes=await File('../../work/toolchain/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();});
  final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:blueNoteTheme(),home:LearningProfilePage(client:ProfileFixture(),userId:'a'*32))));
  await tester.pumpAndSettle();expect(find.text('蓝笔同学'),findsOneWidget);
  await tester.runAsync(()async{await precacheImage(const AssetImage('assets/brand/launcher.png'),key.currentContext!);});
  await tester.pumpAndSettle();
  await tester.runAsync(()async{final picture=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:2);final bytes=await picture.toByteData(format:ui.ImageByteFormat.png);await File('../ui14-achievements.png').writeAsBytes(bytes!.buffer.asUint8List());picture.dispose();});
  await tester.tap(find.text('初次记录'));await tester.pumpAndSettle();expect(find.text('优秀 · 50 条'),findsOneWidget);expect(find.text('卓越 · 200 条'),findsOneWidget);
  Navigator.of(tester.element(find.text('优秀 · 50 条'))).pop();await tester.pumpAndSettle();
  await tester.tap(find.byType(Switch));await tester.pumpAndSettle();expect(find.text('版本延展者'),findsNothing);
  tester.view.physicalSize=const Size(320,700);await tester.pumpAndSettle();expect(tester.takeException(),isNull);
 });
}
