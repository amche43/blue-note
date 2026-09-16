import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blue_note/community.dart';
import 'package:blue_note/domain.dart';
import 'package:blue_note/improvements_page.dart';
import 'package:blue_note/main.dart';

class ProposalClient extends CommunityClient {
  Json? sent;bool fail=true;
  ProposalClient():super({});
  @override Future<Json> request(String method,String path,[Json? body])async{
    sent=body;
    if(fail)throw const FormatException('原文已更新，请刷新');
    return {'id':'test','status':'pending'};
  }
}
void main(){
  testWidgets('Proposal keeps original and draft on failure; submits the selected field with revision', (tester)async{
    final client=ProposalClient();
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme:blueNoteTheme(),home:Builder(builder:(ctx)=>Scaffold(body:TextButton(onPressed:()=>Navigator.push<void>(ctx,MaterialPageRoute(builder:(_)=>ImprovementEditor(client:client,path:'/test',entry:{'id':'q','revision':'baseline','package':{'question':{'title':'极限题','answer':'原解析'}}}))),child:const Text('打开'))))));
    await tester.tap(find.text('打开'));await tester.pumpAndSettle();
    expect(find.text('原解析'),findsWidgets);
    await tester.enterText(find.byType(TextField).first,'更完整的推导');
    await tester.enterText(find.byType(TextField).last,'先检查使用条件');
    await tester.scrollUntilVisible(find.text('提交给作者核对'),250,scrollable:find.byType(Scrollable).first);
    await tester.tap(find.text('提交给作者核对'));await tester.pumpAndSettle();
    expect(find.text('原文已更新，请刷新'),findsOneWidget);
    expect(client.sent!['base'],'baseline');expect(client.sent!['field'],'answer');expect(client.sent!['after'],'更完整的推导');
    final rid=client.sent!['requestId'];client.fail=false;
    await tester.ensureVisible(find.text('提交给作者核对'));await tester.tap(find.text('提交给作者核对'));await tester.pumpAndSettle();
    expect(client.sent!['requestId'],rid);expect(find.text('打开'),findsOneWidget);expect(tester.takeException(),isNull);
  });
}
