import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/study_tools.dart';

StudyEvent success(String id, int at, {bool correct = true}) => StudyEvent(
  id: id.padRight(32,'0'), lessonId: 'math-symmetry', type: 'attempt', at: at,
  payload: {'rating':correct ? 'good' : 'again','correct':correct,'assisted':false,'reason':'暂未判断','variantId':'v'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Same-day repetition does not inflate independent validation or postpone due date', () {
    final first = success('a',1000);
    final repeat = success('b',2000);
    final progress = Progress.fromEvents([repeat,first]);
    expect(progress.independent,1);
    expect(progress.attempts,2);
    expect(progress.due,DateTime.fromMillisecondsSinceEpoch(1000).add(const Duration(days:1)));
    final afterDay = success('c',1000+const Duration(days:1).inMilliseconds);
    expect(Progress.fromEvents([first,repeat,afterDay]).independent,2);
    expect(Progress.fromEvents([first,success('d',3000,correct:false)]).independent,0);
  });
  testWidgets('Recall appends to notes, protects unsaved input and never records a scored attempt', (tester) async {
    tester.view.physicalSize = const Size(320,740); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=(await tester.runAsync(() => StudyStore.open(factory:databaseFactoryFfiNoIsolate,path:inMemoryDatabasePath)))!;
    await store.note('math-symmetry','原来的总结');
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>Navigator.push<void>(context,
      MaterialPageRoute(builder:(_)=>RecallPage(store:store,lesson:store.lessons.first))),child:const Text('回想'))))));
    await tester.tap(find.text('回想'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first,'区间与被积函数存在对称');
    await tester.pumpAndSettle();
    await tester.pageBack();await tester.pumpAndSettle();
    expect(find.text('这次回想还没保存'),findsOneWidget);
    await tester.tap(find.text('继续编辑'));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('把这次回想追加到笔记'),180,scrollable:find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(find.text('把这次回想追加到笔记')), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('把这次回想追加到笔记'));await tester.pumpAndSettle();
    expect(store.progress('math-symmetry').note,startsWith('原来的总结'));
    expect(store.progress('math-symmetry').note,contains('区间与被积函数存在对称'));
    expect(store.progress('math-symmetry').attempts,0);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();await store.db.close();store.dispose();
  });
  testWidgets('Practice center filters using latest attempts and handles empty favorites', (tester) async {
    final store=(await tester.runAsync(() => StudyStore.open(factory:databaseFactoryFfiNoIsolate,path:inMemoryDatabasePath)))!;
    await store.merge([success('a',1000,correct:false)]);
    await tester.pumpWidget(MaterialApp(home:StudyCenter(store:store,openLesson:(_,_)async{})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待再练'));await tester.pumpAndSettle();
    expect(find.text(store.lessons.first.title),findsOneWidget);
    await store.merge([success('b',2000)]);await tester.pumpAndSettle();
    expect(find.text(store.lessons.first.title),findsNothing);
    await tester.tap(find.text('收藏'));await tester.pumpAndSettle();
    expect(find.text('这里暂时没有题目，可以切换筛选条件。'),findsOneWidget);
    await store.setting('favorite:math-symmetry','true');await tester.pumpAndSettle();
    expect(find.text(store.lessons.first.title),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());await store.db.close();store.dispose();
  });
}
