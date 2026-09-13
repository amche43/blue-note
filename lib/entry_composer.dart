import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'questions.dart';
import 'notebooks.dart';
import 'photo_import.dart';

class EntryComposer extends StatefulWidget {
  final StudyStore store;
  const EntryComposer({super.key,required this.store});
  @override State<EntryComposer> createState()=>_EntryComposerState();
}
class _EntryComposerState extends State<EntryComposer> {
  final title=TextEditingController(),prompt=TextEditingController(),breakthrough=TextEditingController(),thought=TextEditingController(),reason=TextEditingController(),summary=TextEditingController(),subject=TextEditingController(text:'高等数学');
  Json? capture;
  int step=0;
  bool busy=false,dirty=false;
  String kind='question',book='',error='';
  @override void dispose(){for(final c in [title,prompt,breakthrough,thought,reason,summary,subject]){c.dispose();}super.dispose();}
  Future<void> save()async{
    setState((){busy=true;error='';});
    try{
      final id=await widget.store.saveQuestion({...blankQuestion(),'title':title.text.trim().isEmpty?prompt.text.trim().split('\n').first.substring(0,prompt.text.trim().split('\n').first.length.clamp(0,60)):title.text,'prompt':prompt.text,'subject':subject.text,'contentKind':kind,
        'action':breakthrough.text,'firstThought':thought.text,'errorReason':reason.text,'summary':summary.text,
        'notebookId':book,'notebookTitle':notebooks(widget.store)[book]??''},capture:capture);
      if(mounted){setState((){dirty=false;busy=false;});WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context,id);});}
    }catch(e){if(mounted)setState((){busy=false;error=e is FormatException?e.message:'保存未完成，请重试';});}
  }
  Widget input(TextEditingController c,String label,{int lines=1,int max=4000})=>Padding(padding:const EdgeInsets.only(bottom:16),child:TextField(controller:c,onChanged:(_)=>setState(()=>dirty=true),enabled:!busy,minLines:lines,maxLines:lines+3,maxLength:max,decoration:InputDecoration(labelText:label)));
  @override Widget build(BuildContext context)=>PopScope<String>(canPop:!dirty&&!busy,onPopInvokedWithResult:(didPop,result)async{
    if(didPop||busy)return;
    final leave=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('放弃尚未保存的记录？'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('继续整理')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('放弃'))]));
    if(leave==true&&mounted){setState(()=>dirty=false);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}
  },child:Scaffold(appBar:AppBar(title:const Text('记录新的学习内容')),body:ListView(padding:const EdgeInsets.all(24),children:[
    Text(['1 · 记录内容','2 · 写下自己的理解','3 · 加入学习本'][step],style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:16),
    if(step==0)...[
      const Text('先记录下来，理解可以慢慢完善。'),
      OutlinedButton.icon(onPressed:busy?null:()async{
        if(prompt.text.trim().isNotEmpty){
          final replace=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('用识别结果替换现有正文？'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('保留正文')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('继续识别'))]));
          if(replace!=true||!context.mounted)return;
        }
        final result=await Navigator.push<Json>(context,MaterialPageRoute(builder:(_)=>PhotoImportPage(store:widget.store)));
        if(result!=null&&mounted)setState((){prompt.text=result['text'] as String;capture=result['capture'] as Json;dirty=true;});
      },icon:const Icon(Icons.document_scanner_outlined),label:const Text('拍照 / 相册识别')),
      DropdownButton<String>(value:kind,items:const[DropdownMenuItem(value:'question',child:Text('错题 / 例题')),DropdownMenuItem(value:'knowledge',child:Text('知识卡片'))],onChanged:busy?null:(v)=>setState((){kind=v!;book='';dirty=true;})),
      input(title,'标题（可选，留空从正文提取）',max:120),input(subject,'学科',max:60),input(prompt,kind=='knowledge'?'知识内容':'题目正文',lines:5,max:18000),
      const Text('公式和知识点目前请人工核对，保存后可在完整编辑中补充。'),
    ],
    if(step==1)...[
      const Text('真正重要的是，你是怎么想的。以下都可以稍后补充。'),
      input(breakthrough,'关键突破点：看到什么，就该想到什么',lines:3),
      ExpansionTile(title:const Text('多记一点思考（可选）'),children:[input(thought,'我的第一反应',lines:2),if(kind=='question')input(reason,'我的错误原因',lines:2),input(summary,'一句话总结',lines:2)]),
    ],
    if(step==2)...[
      DropdownButtonFormField<String>(initialValue:book,isExpanded:true,decoration:const InputDecoration(labelText:'把它放在哪里？'),items:[const DropdownMenuItem(value:'',child:Text('暂不分本，先保存')),...notebooks(widget.store).entries.where((e)=>isKnowledgeBook(widget.store,e.key)==(kind=='knowledge')).map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value,overflow:TextOverflow.ellipsis)))],onChanged:busy?null:(v)=>setState(()=>book=v!)),
      TextButton(onPressed:busy?null:()async{
        await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>NotebooksPage(store:widget.store,knowledge:kind=='knowledge',openLesson:(_)async{})));
        if(mounted)setState((){});
      },child:const Text('创建 / 管理学习本')),
      const Text('保存为私有内容。公开发布在学习本整理完成后单独确认。'),
    ],
    if(error.isNotEmpty)Text(error,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    const SizedBox(height:20),FilledButton(onPressed:busy?null:(){
      if(step==0&&(prompt.text.trim().isEmpty||subject.text.trim().isEmpty)){setState(()=>error='请填写正文和学科');return;}
      if(step<2){setState((){step++;error='';});}else{save();}
    },child:Text(busy?'正在保存…':step==2?'保存学习条目':'下一步')),
    if(step>0)TextButton(onPressed:busy?null:()=>setState(()=>step--),child:const Text('上一步')),
  ])));
}
