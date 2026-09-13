import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/main.dart';
import 'package:blue_note/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); sqfliteFfiInit();
  testWidgets('Challenge flow records one answer and persists a note', (tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=(await tester.runAsync(() => StudyStore.open(factory:databaseFactoryFfiNoIsolate,path:inMemoryDatabasePath)))!;
    await store.setting('mode','challenge');
    await tester.pumpWidget(BlueNoteApp(store:store));await tester.pumpAndSettle();
    expect(find.text('继续学习'),findsOneWidget);
    await tester.tap(find.text('继续学习 ›'));await tester.pumpAndSettle();
    expect(find.text('我做完了，核对解答'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('直接试做变式 →'),200,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('直接试做变式 →'));await tester.pumpAndSettle();
    await tester.tap(find.text('A   π/4'));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('完成本题，安排复习'),220,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('完成本题，安排复习'));await tester.pumpAndSettle();
    expect(store.events.where((e)=>e.type=='attempt').length,1);
    expect(store.progress('math-symmetry').independent,1);
    await tester.scrollUntilVisible(find.text('补充我的蓝笔总结'),200,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('补充我的蓝笔总结'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'看到对称区间，先试换元。');
    await tester.tap(find.text('保存笔记'));await tester.pumpAndSettle();
    expect(store.progress('math-symmetry').note,'看到对称区间，先试换元。');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
    await store.db.close();store.dispose();
  });
  testWidgets('Every formula and linked knowledge reference is valid', (tester) async {
    final raw=jsonDecode((await tester.runAsync(() => rootBundle.loadString('assets/lessons.json')))!) as Map<String,dynamic>;
    for(final lesson in raw['lessons'] as List){
      final concepts=(lesson['concepts'] as List).map((c)=>c['id']).toSet();
      for(final step in lesson['steps'] as List){
        for(final match in RegExp(r'\[\[([^|]+)\|([^\]]+)\]\]').allMatches(step['text'] as String)){
          expect(concepts.contains(match.group(1)),isTrue,reason:lesson['id'] as String);
        }
      }
      for(final node in [lesson,...lesson['steps'],...lesson['concepts'],...lesson['variants']]){
        if(node['formula']!=null){
          bool failed=false;
          await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(scrollDirection:Axis.horizontal,child:
            Math.tex(node['formula'] as String,onErrorFallback:(_){failed=true;return const Text('invalid');})))));
          await tester.pumpAndSettle();expect(failed,isFalse,reason:node['formula'] as String);expect(tester.takeException(),isNull);
        }
      }
    }
  });
}
