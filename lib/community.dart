import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'questions.dart';
import 'store.dart';
import 'hall.dart';
import 'brand.dart';
import 'package:flutter_math_fork/flutter_math.dart';

const feedbackLabels = {'draft': '尚未提交', 'pending': '待处理', 'reviewing': '核对中', 'resolved': '已处理'};

class CommunityClient {
  final Json config;
  CommunityClient(this.config);
  static Json parse(String raw, {bool allowAnonymous=false}) {
    final value = jsonDecode(raw);
    if (value is! Json) throw const FormatException('连接配置格式不正确');
    final uri = Uri.tryParse(value['url'] is String ? value['url'] as String : '');
    if (uri == null || uri.scheme != 'https' || !['10.0.2.2', '127.0.0.1', 'localhost'].contains(uri.host) ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment || !['', '/'].contains(uri.path)) {
      throw const FormatException('本机测试仅支持本机或 Android 模拟器的 HTTPS 地址');
    }
    if ((!allowAnonymous && (value['token'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['token'] as String))) ||
        value['certificate'] is! String || (value['certificate'] as String).length > 16000) {
      throw const FormatException('连接口令或证书不正确');
    }
    SecurityContext(withTrustedRoots: false).setTrustedCertificatesBytes(utf8.encode(value['certificate'] as String));
    return value;
  }

  Future<Json> request(String method, String path, [Json? data]) async {
    final security = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(config['certificate'] as String));
    final client = HttpClient(context: security)..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.openUrl(method, Uri.parse(config['url'] as String).replace(path: Uri.parse(path).path, query: Uri.parse(path).hasQuery ? Uri.parse(path).query : null))
        .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      if(config['token'] is String)req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config['token']}');
      if (data != null) {
        req.headers.contentType = ContentType.json;
        final bytes = utf8.encode(jsonEncode(data));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final timeout = Duration(seconds: path == '/v1/ocr' ? 90 : 15);
      final res = await req.close().timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in res.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 20 * 1024 * 1024) throw const FormatException('后台返回内容过大');
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Json) throw const FormatException('后台响应格式不正确');
      if (res.statusCode != 200) throw FormatException(value['error'] as String? ?? '后台暂不可用');
      return value;
    } on SocketException {
      throw const FormatException('未连接到本机后台。请确认电脑上的后台窗口仍开着。');
    } on HandshakeException {
      throw const FormatException('后台证书不匹配，请重新导入本机生成的连接配置。');
    } finally {
      client.close(force: true);
    }
  }
}

class FeedbackRepository {
  final StudyStore store;
  FeedbackRepository(this.store);
  List<Json> get items => store.settings.entries.where((e) => e.key.startsWith('feedback:'))
    .map((e) => jsonDecode(e.value) as Json).toList().reversed.toList();
  Future<void> save(Json item) => store.setting('feedback:${item['requestId']}', jsonEncode(item));
  Future<void> draft(String lesson, String title, String body) async {
    if (body.trim().isEmpty || body.length > 8000) throw const FormatException('请填写反馈，最多 8000 字');
    await save({'requestId': newId(), 'lesson': lesson, 'title': title, 'body': body.trim(),
      'status': 'draft', 'reply': '', 'account': '', 'server': ''});
  }
  Future<void> submit(Json item, CommunityClient client, String account) async {
    final url = client.config['url'];
    if (item['account'] != '' && (item['account'] != account || item['server'] != url)) {
      throw const FormatException('请连接创建此提交记录时使用的后台和测试账户');
    }
    final bound = {...item, 'account': account, 'server': url};
    await save(bound); // Persist the retry identity before the request leaves the device.
    final reply = await client.request('POST', '/v1/feedback', {
      for (final key in ['requestId', 'lesson', 'title', 'body']) key: item[key],
    });
    if (reply['id'] is! String || !['pending', 'reviewing', 'resolved'].contains(reply['status'])) {
      throw const FormatException('后台未返回有效回执，保留原状态');
    }
    await save({...bound, 'id': reply['id'], 'status': reply['status'], 'reply': reply['reply'] ?? ''});
  }
  Future<void> refresh(CommunityClient client, String account) async {
    final result = await client.request('GET', '/v1/feedback');
    for (final remote in result['items'] as List) {
      final matches = items.where((e) => e['requestId'] == remote['request_id'] &&
        e['account'] == account && e['server'] == client.config['url']);
      if (matches.isNotEmpty && ['pending', 'reviewing', 'resolved'].contains(remote['status'])) {
        await save({...matches.first, 'id': remote['id'], 'status': remote['status'], 'reply': remote['reply']});
      }
    }
  }
}

class CommunityPage extends StatefulWidget {
  final StudyStore store;
  final bool feedbackOnly;
  final String? initialBook;
  const CommunityPage({super.key, required this.store, this.feedbackOnly = false,this.initialBook});
  @override State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  CommunityClient? client;
  String? account;
  String name = '', error = '';
  bool busy = false;
  List<Json> questions = [], books = [];
  String? selectedBook;
  FeedbackRepository get feedback => FeedbackRepository(widget.store);
  @override void initState() {
    super.initState();
    selectedBook=widget.initialBook;
    final raw = widget.store.settings['community'];
    if (raw != null) {
      try { client = CommunityClient(CommunityClient.parse(raw)); } catch (_) { error = '请重新导入连接配置'; }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && client != null) reload(); });
  }
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = ''; });
    try { await action(); } catch (e) {
      if (mounted) setState(() => error = e is FormatException ? e.message : '操作未确认完成，请重试；反馈会保留原状态。');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> reload() => run(() async {
    final me = await client!.request('GET', '/v1/me');
    account = me['id'] as String; name = me['name'] as String;
    await feedback.refresh(client!, account!);
    if (!widget.feedbackOnly) {
      books = ((await client!.request('GET', '/v1/notebooks'))['items'] as List).cast<Json>();
      final data = await client!.request('GET', selectedBook == null ? '/v1/questions' : '/v1/notebooks/$selectedBook');
      questions = (data['items'] as List).cast<Json>();
    }
  });
  Future<void> configure() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('连接本机后台'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('粘贴电脑生成的连接配置。里面含有测试账户口令，请勿发给别人。'),
        TextField(controller: controller, maxLines: 5, decoration: const InputDecoration(labelText: '连接配置')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('连接'))]));
    // Dispose after the dialog transition has released its text input.
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (raw == null || !mounted) return;
    await run(() async {
      final next = CommunityClient(CommunityClient.parse(raw));
      final me = await next.request('GET', '/v1/me');
      await widget.store.setting('community', jsonEncode(next.config));
      client = next; account = me['id'] as String; name = me['name'] as String;
      questions = []; selectedBook = null;
    });
    if (client != null && mounted) await reload();
  }
  Future<void> publish() async {
    final options = widget.store.questions.entries.where((e) => e.value['deleted'] == false).toList();
    String? selected;
    bool consent = false;
    final chosen = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: const Text('发布我的题目 / 知识卡片'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (options.isEmpty) const Text('请先在“我的”中添加题目。'),
        ...options.map((e) => ListTile(title: Text(e.value['title'] as String), subtitle: Text((e.value['notebookTitle'] as String? ?? '').isEmpty ? '未分本' : '${e.value['notebookTitle']} · 第${e.value['questionNumber']}题'),
          leading: Icon(selected == e.key ? Icons.radio_button_checked : Icons.radio_button_off),
          onTap: () => update(() => selected = e.key))),
        if (selected != null) ...[
          const Divider(), const Text('本次公开内容预览'),
          Text(['notebookTitle','questionNumber','title','subject','chapter','prompt','formula','answer','trigger','action','conditions','pitfall','firstThought','errorReason','summary','source']
            .map((k) => widget.store.questions[selected]![k]).where((v) => v != '').join('\n\n')),
        ],
        CheckboxListTile(value: consent, onChanged: (v) => update(() => consent = v ?? false),
          title: const Text('我有权分享并同意公开以上内容、思考过程及来源'),
          subtitle: const Text('不包含私人笔记和学习记录。撤回后，别人已下载的副本仍会保留。')),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      TextButton(onPressed: selected != null && consent ? () => Navigator.pop(ctx, selected) : null, child: const Text('确认发布'))])));
    if (chosen == null || !mounted) return;
    await run(() async {
      final revisions = widget.store.events.where((e) => e.type == 'question' && e.lessonId == chosen).toList()..sort(compareEvents);
      await client!.request('POST', '/v1/questions', {'consent': true, 'requestId': revisions.last.id,
        'question': widget.store.questions[chosen]});
    });
    if (mounted && error.isEmpty) await reload();
  }
  Future<void> openReference() async {
    final input=TextEditingController();
    final raw=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('打开题目引用'),content:TextField(controller:input,maxLines:3),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(ctx,input.text),child:const Text('打开'))]));
    Future<void>.delayed(const Duration(milliseconds:350),input.dispose);
    if(raw==null||!mounted)return;
    await run(()async{
      final id=RegExp(r'blue-note:q:(user-[a-f0-9]{32})(?![a-f0-9])').firstMatch(raw)?.group(1);
      if(id==null)throw const FormatException('请粘贴从共享题目复制的完整引用');
      final question=await client!.request('GET','/v1/questions/$id');
      if(mounted)await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>SharedQuestionPage(store:widget.store,client:client!,initial:question)));
    });
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.feedbackOnly ? '我的纠错反馈' : '学习社区 · 本机测试'), actions: [
      IconButton(tooltip: '连接设置', onPressed: busy ? null : configure, icon: const Icon(Icons.settings_outlined)),
      IconButton(tooltip: '刷新', onPressed: busy || client == null ? null : reload, icon: const Icon(Icons.refresh)),
    ]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(account == null ? '连接本机后台后使用社区功能' : '测试账户：$name'),
      if (client == null) TextButton(onPressed: busy ? null : configure, child: const Text('导入连接配置')),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (!widget.feedbackOnly) ...[
        FilledButton.icon(onPressed:busy||client==null?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>HallPage(client:client!,store:widget.store))),icon:const Icon(Icons.travel_explore),label:const Text('进入大厅 · 搜索知识本与错题本')),
        const SizedBox(height:12),
        const Text('只显示作者确认公开的内容。私人本子不会自动整本上传。'),
        Wrap(spacing:8,children:[ChoiceChip(label:const Text('全部分享'),selected:selectedBook==null,onSelected:busy?null:(_)async{setState(()=>selectedBook=null);await reload();}),
          ...books.map((b)=>ChoiceChip(label:Text('${b['title']} · ${b['name']} (${b['count']})'),selected:selectedBook==b['id'],onSelected:busy?null:(_)async{setState(()=>selectedBook=b['id'] as String);await reload();}))]),
        TextButton.icon(onPressed:busy||client==null?null:openReference,icon:const Icon(Icons.link),label:const Text('粘贴题目引用')),

        FilledButton.icon(onPressed: busy || account == null ? null : publish, icon: const Icon(Icons.add), label: const Text('发布我的题目 / 知识卡片')),
        if (!busy && questions.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('还没有共享题目。你的私人题目不会自动出现在这里。')),
        ...questions.map((q) => Card(child: ListTile(title: Text(q['package']['question']['title'] as String),
          subtitle: Text('${q['package']['question']['notebookTitle'] ?? ''} ${(q['package']['question']['questionNumber'] ?? '') == '' ? '' : '第${q['package']['question']['questionNumber']}题'} · ${q['package']['author']} · ${q['likes']} 人点赞'), trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : () async {
            await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => SharedQuestionPage(store: widget.store, client: client!, initial: q)));
            if (mounted) await reload();
          }))),
        TextButton(onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CommunityPage(store: widget.store, feedbackOnly: true))), child: const Text('查看我的纠错反馈')),
      ] else ...[
        const Text('尚未提交：未获得后台回执；断线后可重试，不会重复生成反馈。只有当前测试账户能查询自己的反馈。'),
        if (feedback.items.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('暂时没有反馈。在题目页点击“纠错反馈”即可填写。')),
        ...feedback.items.map((f) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(feedbackLabels[f['status']] ?? '尚未提交'), Text(f['body'] as String),
          if ((f['reply'] as String).isNotEmpty) Text('处理回复：${f['reply']}'),
          if (f['status'] == 'draft') TextButton(onPressed: busy || account == null ? null : () => run(() => feedback.submit(f, client!, account!)), child: const Text('提交 / 重试')),
        ])))),
      ],
    ]),
  );
}

Future<void> createFeedback(BuildContext context, StudyStore store, String id, String title) async {
  final controller = TextEditingController();
  final body = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('纠错反馈'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(title), const Text('指出有疑问的步骤，也可以补充你的推导。先保存为“尚未提交”；提交时仅发送题目编号、标题和这段反馈。'),
      TextField(controller: controller, maxLines: 6, maxLength: 8000, decoration: const InputDecoration(labelText: '哪里有问题？')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      TextButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('保存反馈'))]));
  Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
  if (body == null) return;
  await FeedbackRepository(store).draft(id, title, body);
  if (context.mounted) await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CommunityPage(store: store, feedbackOnly: true)));
}

class SharedQuestionPage extends StatefulWidget {
  final StudyStore store;
  final CommunityClient client;
  final Json initial;
  const SharedQuestionPage({super.key, required this.store, required this.client, required this.initial});
  @override State<SharedQuestionPage> createState() => _SharedQuestionPageState();
}
class _SharedQuestionPageState extends State<SharedQuestionPage> {
  late Json question = widget.initial;
  List<Json> comments = [];
  final comment = TextEditingController();
  String commentId = newId(), error = '';
  bool busy = false;
  String get path => '/v1/questions/${question['id']}';
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => run(load)); }
  @override void dispose() { comment.dispose(); super.dispose(); }
  Future<void> load() async {
    question = await widget.client.request('GET', path);
    comments = ((await widget.client.request('GET', '$path/comments'))['items'] as List).cast<Json>();
  }
  Future<void> run(Future<void> Function() fn) async {
    if (!mounted || busy) return;
    setState(() { busy = true; error = ''; });
    try { await fn(); } catch (e) { if (mounted) error = e is FormatException ? e.message : '操作未确认完成，请稍后重试'; }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    final q = question['package']['question'] as Json;
    return Scaffold(appBar: AppBar(title: Text(q['contentKind']=='knowledge'?'知识条目':'学习条目')), body: ListView(padding: const EdgeInsets.all(20), children: [
      if (busy) const LinearProgressIndicator(), if (error.isNotEmpty) Text(error),
      Text(q['title'] as String, style: Theme.of(context).textTheme.headlineSmall),
      Text('${question['package']['author']} · 用户分享，尚未审核'),
      TextButton.icon(onPressed: busy ? null : () => run(() async {
        question = await widget.client.request('PUT', '$path/like', {'liked': question['liked'] != true});
      }), icon: Icon(question['liked'] == true ? Icons.thumb_up : Icons.thumb_up_outlined), label: Text('${question['liked']==true?'已点赞 · 点击取消':'给这条内容点赞'} (${question['likes']})')),

      if ((q['notebookTitle'] as String? ?? '').isNotEmpty) Text('${q['notebookTitle']} · 第${q['questionNumber']}题'),
      TextButton.icon(onPressed:busy?null:()=>run(()async{
        await Clipboard.setData(ClipboardData(text:'${q['notebookTitle'] ?? '共享题目'} 第${q['questionNumber'] ?? ''}题 · ${q['title']}\nblue-note:q:${question['id']}'));
        if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已复制引用，可在同一后台的共享题库粘贴打开')));
      }),icon:const Icon(Icons.link),label:const Text('复制本题引用')),

      ...['prompt','formula','firstThought','errorReason','answer','trigger','action','conditions','pitfall','summary','source'].where((k)=>q[k] is String&&q[k]!='').map((k)=>Container(
        margin:const EdgeInsets.symmetric(vertical:12),padding:const EdgeInsets.all(14),
        decoration:BoxDecoration(color:k=='errorReason'||k=='pitfall'?const Color(0xffffedf1):Colors.white,borderRadius:BorderRadius.circular(10)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Container(padding:const EdgeInsets.only(left:8),decoration:const BoxDecoration(border:Border(left:BorderSide(color:Color(0xff2878f0),width:3))),child:Text({'prompt':'学习内容','formula':'公式','firstThought':'我的理解','errorReason':'错误原因','answer':'正确思路','trigger':'识别线索','action':'关键突破点','conditions':'适用条件','pitfall':'易错提醒','summary':'一句话总结','source':'参考资料'}[k]!,style:const TextStyle(fontSize:15,fontWeight:FontWeight.bold,color:Color(0xff172952)))),
          const SizedBox(height:10),if(k=='formula')SingleChildScrollView(scrollDirection:Axis.horizontal,child:Math.tex(q[k] as String,onErrorFallback:(_)=>SelectableText(q[k] as String)))else SelectableText(q[k] as String,style:const TextStyle(fontSize:15,height:1.7)),
        ]))),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final fresh = await widget.client.request('GET', path);
        decodeQuestionPackage(jsonEncode(fresh['package']));
        await widget.store.importQuestionPackage(jsonEncode(fresh['package']));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存到私人题库，重复下载不会覆盖你的修改')));
      }), child: const Text('下载到我的题库')),
      TextButton(onPressed: busy ? null : () => createFeedback(context, widget.store, question['id'] as String, q['title'] as String), child: const Text('纠错反馈')),
      if (question['mine'] == true) TextButton(onPressed: busy ? null : () async {
        final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('撤回这道题？'),
          content: const Text('共享题库将不再显示。其他人已下载的副本仍会保留。'), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('撤回'))]));
        if (yes == true && mounted) await run(() async { await widget.client.request('DELETE', path); if (context.mounted) Navigator.pop(context); });
      }, child: const Text('撤回我的发布')),
      const Divider(), const Text('围绕这条内容交流 · 最近200条'),
      TextButton.icon(onPressed:busy?null:()async{
        final chosen=await showModalBottomSheet<int>(context:context,builder:(ctx)=>GridView.count(crossAxisCount:5,shrinkWrap:true,children:List.generate(stickerNames.length,(i)=>InkWell(onTap:()=>Navigator.pop(ctx,i),child:Column(children:[BlueSticker(i,width:52),Text(stickerNames[i],style:const TextStyle(fontSize:12))])))));
        if(chosen!=null&&mounted){comment.text+='\n[蓝笔表情:${stickerNames[chosen]}]';}
      },icon:const Icon(Icons.emoji_emotions_outlined),label:const Text('添加蓝笔表情')),
      TextField(controller: comment, enabled: !busy, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(labelText: '说说你的理解')),
      TextButton(onPressed: busy ? null : () => run(() async {
        if (comment.text.trim().isEmpty) throw const FormatException('请先填写评论');
        await widget.client.request('POST', '$path/comments', {'requestId': commentId, 'body': comment.text.trim()});
        comment.clear(); commentId = newId(); await load();
      }), child: const Text('发布评论')),
      ...comments.map((c) => ListTile(leading:const BlueAvatar(width:30),title: Column(crossAxisAlignment:CrossAxisAlignment.start,children:(c['body'] as String).split('\n').map((line){final index=stickerNames.indexWhere((name)=>line=='[蓝笔表情:$name]');return index<0?Text(line):Semantics(label:stickerNames[index],child:BlueSticker(index));}).toList()), subtitle: Text(c['name'] as String),
        trailing: c['mine'] == 1 ? IconButton(tooltip: '删除我的评论', icon: const Icon(Icons.delete_outline), onPressed: busy ? null : () => run(() async {
          await widget.client.request('DELETE', '/v1/comments/${c['id']}'); await load();
        })) : null)),
    ]));
  }
}
