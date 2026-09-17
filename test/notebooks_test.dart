import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:blue_note/questions.dart';
import 'package:blue_note/store.dart';
import 'package:blue_note/photo_import.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  test('Notebook numbers survive deletion, backup and old question formats',()async{
    final store=await StudyStore.open(factory:databaseFactoryFfi,path:inMemoryDatabasePath);
    final q={...blankQuestion(),'title':'题目','prompt':'计算','notebookId':'book-${'a'*32}','notebookTitle':'数学错题本'};
    final first=await store.saveQuestion(q);final second=await store.saveQuestion(q);
    expect(store.questions[first]!['questionNumber'],'1');expect(store.questions[second]!['questionNumber'],'2');
    await store.deleteQuestion(first);
    final third=await store.saveQuestion(q);expect(store.questions[third]!['questionNumber'],'3');
    final restored=await StudyStore.open(factory:databaseFactoryFfi,path:inMemoryDatabasePath);
    await restored.restore(store.backup());expect(restored.questions[third]!['notebookTitle'],'数学错题本');
    final old={...blankQuestion(),'title':'旧题','prompt':'旧题干'}..remove('notebookId')..remove('notebookTitle')..remove('questionNumber');
    expect(validateQuestion(old)['notebookId'],'');
    final copy={...store.questions[second]!, 'notebookId':'book-${'b'*32}'};
    final package=encodeQuestionPackage('user-${'c'*32}',copy,consent:true,author:'同学');
    final imported=await restored.importQuestionPackage(package);
    expect(await restored.importQuestionPackage(package),imported);
    await store.db.close();store.dispose();await restored.db.close();restored.dispose();
  });
  testWidgets('Photo text requires explicit verification, edits invalidate verification',(tester)async{
    final store=(await tester.runAsync(()=>StudyStore.open(factory:databaseFactoryFfiNoIsolate,path:inMemoryDatabasePath)))!;
    await tester.pumpWidget(MaterialApp(home:PhotoImportPage(store:store)));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'识别出的题干');await tester.pumpAndSettle();
    final save=find.widgetWithText(FilledButton,'填入题干，继续编辑');
    await tester.scrollUntilVisible(save, 200, scrollable: find.byType(Scrollable).first);await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed,isNull);
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed,isNotNull);
    await tester.enterText(find.byType(TextField),'修改后的条件');await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed,isNull);
    await tester.pumpWidget(const SizedBox());await store.db.close();store.dispose();
  });
}
