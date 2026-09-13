import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';

class EntryHistory extends StatefulWidget {
  final StudyStore store;
  final String id;
  const EntryHistory({super.key,required this.store,required this.id});
  @override State<EntryHistory> createState()=>_EntryHistoryState();
}
class _EntryHistoryState extends State<EntryHistory> {
  late final data=widget.store.db.query('capture_records',where:'lesson_id=?',whereArgs:[widget.id]);
  @override Widget build(BuildContext context){
    final revisions=widget.store.events.where((e)=>e.type=='question'&&e.lessonId==widget.id).toList()..sort(compareEvents);
    return Scaffold(appBar:AppBar(title:const Text('录入与修改历史')),body:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('原始识别与确认记录',style:TextStyle(fontSize:22)),
      FutureBuilder(future:data,builder:(context,snapshot){
        if(snapshot.hasError)return const Text('录入记录暂时无法读取');
        if(!snapshot.hasData)return const LinearProgressIndicator();
        if(snapshot.data!.isEmpty)return const Text('这条内容没有保存在本机的照片识别记录。');
        final record=jsonDecode(snapshot.data!.first['data'] as String) as Json;
        return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(record['source_image'] is String)Image.memory(base64Decode(record['source_image'] as String),height:300,fit:BoxFit.contain),
          const Text('录入时的图片（已压缩），仅保存在当前设备。'),
          ExpansionTile(title:const Text('OCR 原始结果'),children:[SelectableText(const JsonEncoder.withIndent('  ').convert(record['ocr_raw']))]),
          ExpansionTile(title:const Text('AI 结构化结果'),children:[Text(record['ai_parsed']==null?'本次没有调用结构化模型，没有生成推测结果。':const JsonEncoder.withIndent('  ').convert(record['ai_parsed']))]),
          ExpansionTile(title:const Text('录入时的用户确认结果'),children:[SelectableText(const JsonEncoder.withIndent('  ').convert(record['user_confirmed']))]),
        ]);
      }),const SizedBox(height:24),const Text('修改历史',style:TextStyle(fontSize:22)),
      const Text('保留每次保存的版本，可阅读对比；这里不会自动覆盖当前内容。'),
      ...revisions.reversed.map((e)=>ExpansionTile(title:Text(DateTime.fromMillisecondsSinceEpoch(e.at).toString().substring(0,16)),subtitle:Text(e.payload['title'] as String),children:[
        ...{'prompt':'内容','firstThought':'我的第一反应','errorReason':'错误原因','action':'关键突破点','summary':'一句话总结','answer':'正确思路'}.entries.where((f)=>(e.payload[f.key] as String? ?? '').isNotEmpty).map((f)=>ListTile(title:Text(f.value),subtitle:SelectableText(e.payload[f.key] as String))),
      ])),
    ]));
  }
}
