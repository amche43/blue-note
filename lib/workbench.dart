import 'package:flutter/material.dart';
import 'brand.dart';
import 'domain.dart';
import 'notebooks.dart';
import 'store.dart';

class LearningWorkbench extends StatelessWidget {
  final StudyStore store;
  final Future<void> Function(Lesson) open;
  final VoidCallback create;
  const LearningWorkbench({super.key,required this.store,required this.open,required this.create});
  @override Widget build(BuildContext context){
    final books=notebooks(store);
    final records=store.events.where((e)=>e.type=='question'&&store.questions[e.lessonId]?['deleted']==false).toList()..sort(compareEvents);
    final recent=records.isEmpty?null:store.lessons.where((l)=>l.id==records.last.lessonId).firstOrNull;
    void showBooks(bool knowledge,{String? id})=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>NotebooksPage(store:store,knowledge:knowledge,openLesson:open,initialBook:id)));
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('继续自己的学习',style:TextStyle(fontSize:28,fontWeight:FontWeight.w600)),Text('Open Your Learning.\n开源你的学习过程。')])),if(recent==null)const BlueMascot(width:82)]),
      const SizedBox(height:20),
      if(recent!=null)ListTile(contentPadding:EdgeInsets.zero,leading:SubjectArt(recent.subject),title:Text(recent.title),subtitle:const Text('最近整理的内容'),trailing:const Icon(Icons.arrow_forward),onTap:()=>open(recent)),
      if(recent==null)const Text('先留下一个问题，或一个终于想通的知识点。'),
      FilledButton.icon(onPressed:create,icon:const Icon(Icons.add),label:const Text('记录新的学习内容')),
      const SizedBox(height:24),const Text('我的学习本',style:TextStyle(fontSize:21,fontWeight:FontWeight.w600)),
      Text('已建立 ${books.length} 本 · 已整理 ${store.questions.values.where((q)=>q['deleted']==false).length} 条内容'),
      Wrap(spacing:12,children:[TextButton(onPressed:()=>showBooks(false),child:const Text('错题本 / 专题整理')),TextButton(onPressed:()=>showBooks(true),child:const Text('必备知识点本'))]),
      ...books.entries.take(4).map((book)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.menu_book_outlined),title:Text(book.value),onTap:()=>showBooks(isKnowledgeBook(store,book.key),id:book.key))),
      const SizedBox(height:16),ContributionGrid(store:store),const SizedBox(height:28),
      const Text('例题与复习',style:TextStyle(fontSize:21,fontWeight:FontWeight.w600)),
    ]);
  }
}
class ContributionGrid extends StatelessWidget {
  final StudyStore store;
  const ContributionGrid({super.key,required this.store});
  @override Widget build(BuildContext context){
    final now=DateTime.now();final today=DateTime(now.year,now.month,now.day);
    String key(DateTime d)=>'${d.year}-${d.month}-${d.day}';
    final counts=<String,int>{};
    for(final e in store.events){if(!['question','note','attempt'].contains(e.type))continue;final k=key(DateTime.fromMillisecondsSinceEpoch(e.at));counts[k]=(counts[k]??0)+1;}
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('学习建设记录 · 近365天'),const Text('记录、修改、笔记与复习；按已保存的历史计算。',style:TextStyle(fontSize:12)),
      SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:List.generate(53,(week)=>Column(children:List.generate(7,(day){
        final index=week*7+day;
        if(index>=365)return const SizedBox(width:12,height:12);
        final date=DateTime(today.year,today.month,today.day-(364-index));final count=counts[key(date)]??0;
        return Tooltip(message:'${key(date)} · $count次记录',child:Container(margin:const EdgeInsets.all(1),width:10,height:10,decoration:BoxDecoration(color:count==0?const Color(0xffe9f1fc):Color.lerp(const Color(0xffbdd7fb),const Color(0xff2878f0),(count.clamp(1,8)-1)/7),borderRadius:BorderRadius.circular(2))));
      }))))),
    ]);
  }
}
