import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'domain.dart';
import 'store.dart';
import 'question_editor.dart';
import 'community.dart';
import 'study_tools.dart';
import 'notebooks.dart';
import 'knowledge_page.dart';
import 'workbench.dart';
import 'brand.dart';
import 'entry_composer.dart';
import 'studio_shell.dart';

const inkBlue = Color(0xff2878f0);
const paper = Color(0xfff8fbff);
const bluePaper = Color(0xffedf2fb);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(BlueNoteApp(store: await StudyStore.open(),showWelcome:true));
  } catch (_) {
    runApp(const MaterialApp(home: Scaffold(body: SafeArea(child: Center(
      child: Padding(padding: EdgeInsets.all(24), child: Text('暂时无法打开学习记录。请关闭后重试；不要卸载应用，以免丢失本地笔记。')),
    )))));
  }
}

class BlueNoteApp extends StatelessWidget {
  final StudyStore store;
  final bool showWelcome;
  const BlueNoteApp({super.key, required this.store,this.showWelcome=false});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '蓝笔', debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'), supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: blueNoteTheme(),
    home: showWelcome?WelcomePage(store:store,child:HomePage(store:store)):HomePage(store: store),
  );
}

ThemeData blueNoteTheme() => ThemeData(
      useMaterial3: true, scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: inkBlue, surface: paper).copyWith(primary:inkBlue,onPrimary:Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: paper, surfaceTintColor: Colors.transparent),
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 16, height: 1.7), bodyLarge: TextStyle(fontSize: 17, height: 1.7)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.selected)?inkBlue:Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.selected)?Colors.white:Colors.blueGrey),
        side: const WidgetStatePropertyAll(BorderSide(color:Color(0xffe3ecfa))),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize:13)),
      )),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
    );

void message(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class HomePage extends StatefulWidget {
  final StudyStore store;
  const HomePage({super.key, required this.store});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int tab = 0;
  String subject = '全部', query = '';
  Timer? timer;
  StudyStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(changed);
    timer = Timer.periodic(const Duration(minutes: 1), (_) => changed());
  }
  void changed() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) changed(); }
  @override
  void dispose() {
    timer?.cancel(); store.removeListener(changed); WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  Future<void> open(Lesson lesson, {bool review = false}) async {
    try {await store.setting('lastOpenedLesson',lesson.id);} catch (_) { /* Learning can continue if this convenience setting fails. */ }
    if(!mounted)return;
    await Navigator.push(context,MaterialPageRoute<void>(builder: (_) => store.questions[lesson.id]?['contentKind']=='knowledge' ? KnowledgePage(store:store,id:lesson.id) : LessonPage(store: store, lesson: lesson, review: review)));
  }
  Future<void> addQuestion() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => QuestionEditor(store: store)));
    if (!mounted || id == null) return;
    final lesson = store.lessons.where((lesson) => lesson.id == id).firstOrNull;
    if (lesson != null) open(lesson);
  }
  Future<void> recordContent()async{
    final id=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>EntryComposer(store:store)));
    if(!mounted||id==null)return;
    final lesson=store.lessons.where((l)=>l.id==id).firstOrNull;
    if(lesson!=null)open(lesson);
  }
  Future<void> importQuestion() async {
    final id = await importQuestionDialog(context, store);
    if (!mounted || id == null) return;
    final lesson = store.lessons.where((lesson) => lesson.id == id).firstOrNull;
    if (lesson != null) open(lesson);
  }

  Widget listTile(Lesson lesson, {bool notes = false, bool review = false}) {
    final progress = store.progress(lesson.id);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(
      color: Colors.white, borderRadius: BorderRadius.circular(18), clipBehavior: Clip.antiAlias, child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(
        notes ? progress.note ?? '' : '${lesson.subject} · ${lesson.chapter}\n${lesson.data['custom'] == true ? '我的题目 · 私人保存' : progress.status}',
        maxLines: notes ? 4 : 2, overflow: TextOverflow.ellipsis)),
      trailing: const Icon(Icons.chevron_right, color: inkBlue),
      onTap: () => notes ? editNote(context, store, lesson) : open(lesson, review: review),
    )));
  }

  void studyCenter() => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => StudyCenter(store: store, openLesson: (lesson, review) => open(lesson, review: review))));

  List<Widget> today() {
    final due = store.due;
    final unseen = store.lessons.where((l) => store.progress(l.id).attempts == 0).toList();
    final next = due.isNotEmpty ? due.first : unseen.isNotEmpty ? unseen.first : store.lessons.first;
    final learned = store.lessons.where((l) => store.progress(l.id).attempts > 0).length;
    return [
      LearningWorkbench(store:store,open:(lesson)=>open(lesson),create:recordContent),

      const Eyebrow('把想通的那一步，留给下一次'),
      const SizedBox(height: 12),
      const Text('补上一个卡点', style: TextStyle(fontSize: 21, height: 1.4, fontWeight: FontWeight.w600)),
      const SizedBox(height: 28),
      BlueBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(due.isNotEmpty ? '到期复习 · ${due.length} 个卡点' : '下一段学习', style: const TextStyle(color: inkBlue)),
        const SizedBox(height: 8), Text(next.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6), Text('${next.subject} · ${next.chapter}'),
      ])),
      const SizedBox(height: 22),
      SegmentedButton<String>(segments: const [
        ButtonSegment(value: 'guided', label: Text('循序渐进')),
        ButtonSegment(value: 'challenge', label: Text('直接挑战')),
      ], selected: {store.guided ? 'guided' : 'challenge'}, onSelectionChanged: (v) async {
        try { await store.setting('mode', v.first); } catch (_) { if (mounted) message(context, '学习方式未保存，请重试'); }
      }),
      const SizedBox(height: 10),
      Text(store.guided ? '例题带路，卡住时逐步揭示提示。' : '先独立判断思路，需要时再求助。', style: const TextStyle(color: Colors.black54, fontSize: 14)),
      const SizedBox(height: 22),
      FilledButton(onPressed: () => open(next, review: due.isNotEmpty), child: Text(due.isNotEmpty ? '开始复习 →' : '开始学习 →')),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: studyCenter, icon: const Icon(Icons.psychology_outlined), label: const Text('复习中心 · 收藏与回想')),
      const SizedBox(height: 12),
      Text('已练习 $learned / ${store.lessons.length} 个学习单元', style: const TextStyle(color: Colors.black54)),
      if (due.isNotEmpty) ...[const SizedBox(height: 24), const Text('该回想的卡点', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 12), ...due.map((l) => listTile(l, review: true))],
      if (due.isEmpty && learned > 0) const Padding(padding: EdgeInsets.only(top: 12), child: Text('当前没有到期复习。也可以在学习页选择单元，直接验证。')),
    ];
  }

  List<Widget> library({bool notes = false}) {
    final filtered = store.lessons.where((l) => (subject == '全部' || l.subject == subject) &&
      '${l.title} ${l.chapter} ${l.prompt} ${l.blue.values.join(' ')} ${store.questions[l.id]?['notebookTitle'] ?? ''} ${store.progress(l.id).note ?? ''}'.contains(query) &&
      (!notes || (store.progress(l.id).note?.isNotEmpty ?? false))).toList();
    return [
      Text(notes ? '我的蓝笔本' : '从例题出发', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), Text(notes ? '用自己的话，保存每一次想通。' : '首批内容来自你的卡点，逐步扩充。', style: const TextStyle(color: Colors.black54)),
      if (!notes) ...[const SizedBox(height: 18),
        FilledButton.icon(onPressed: addQuestion, icon: const Icon(Icons.add), label: const Text('添加我的题目')),
        TextButton.icon(onPressed: importQuestion, icon: const Icon(Icons.download_outlined), label: const Text('导入题目包'))],
      const SizedBox(height: 18),
      TextFormField(key: ValueKey('search-$tab'), initialValue: query, decoration: const InputDecoration(
        hintText: '搜索学习本、方法、章节或笔记', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      if(!notes&&query.trim().isNotEmpty)...notebooks(store).entries.where((e)=>e.value.contains(query.trim())).map((b)=>ListTile(leading:const Icon(Icons.menu_book_outlined),title:Text(b.value),subtitle:const Text('我的学习本'),onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>NotebooksPage(store:store,knowledge:isKnowledgeBook(store,b.key),initialBook:b.key,openLesson:(lesson)=>open(lesson)))))),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: ['全部', ...store.lessons.map((e) => e.subject).toSet()].map((s) => ChoiceChip(
        label: Text(s), selected: subject == s, onSelected: (_) => setState(() => subject = s))).toList()),
      const SizedBox(height: 16),
      if (filtered.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 36), child: Text(
        notes ? '还没有符合条件的笔记。学习例题后，记下让你想通的那一步。' : '没有找到匹配内容，试试其他关键词。')),
      ...filtered.map((l) => listTile(l, notes: notes)),
    ];
  }

  List<Widget> mine() => [
    const Row(children:[BlueAvatar(width:52),SizedBox(width:16),Expanded(child:Text('我的学习成果',style:TextStyle(fontSize:28,fontWeight:FontWeight.w600)))]),
    const SizedBox(height: 14),
    const Text('蓝笔 0.7 · 我的题库\n例题、笔记与复习均可离线使用。'),
    const SizedBox(height: 22),
    ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('添加我的题目'), subtitle: const Text('保存题干、解答与关键点，默认私有'), onTap: addQuestion),
    ListTile(leading: const Icon(Icons.library_books_outlined), title: const Text('我的错题本'), subtitle: const Text('自建本子，按固定题号整理和分享'), onTap: () => Navigator.push<void>(context,MaterialPageRoute(builder: (_) => NotebooksPage(store:store,openLesson:(lesson)=>open(lesson))))),
    ListTile(leading: const Icon(Icons.style_outlined),title:const Text('必备知识点本'),subtitle:const Text('自由创作知识卡片，先回想再展开'),onTap:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>NotebooksPage(store:store,knowledge:true,openLesson:(lesson)=>open(lesson))))),
    ListTile(leading: const Icon(Icons.psychology_outlined), title: const Text('复习与回想'), subtitle: const Text('按卡点筛选、收藏与混合练习'), onTap: studyCenter),
    ListTile(leading: const Icon(Icons.people_outline), title: const Text('学习大厅 · 共享题库'), subtitle: const Text('搜索公开本子，点赞、收藏与交流'), onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CommunityPage(store: store)))),
    ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('我的纠错反馈'), subtitle: const Text('查看提交状态与处理回复'), onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CommunityPage(store: store, feedbackOnly: true)))),
    ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('导出备份'), subtitle: const Text('复制自建题目、笔记与学习记录'), onTap: () => backupDialog(context, store)),
    ListTile(leading: const Icon(Icons.restore), title: const Text('恢复备份'), subtitle: const Text('合并记录，重复内容不重复计数'), onTap: () => importDialog(context, store)),
    ListTile(leading: const Icon(Icons.sync), title: const Text('跨设备同步'), subtitle: Text(store.settings['lastSync'] == null ? '连接你自己的同步服务' : '上次同步 ${store.settings['lastSync']!.substring(0, 16).replaceAll('T', ' ')}'),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SyncPage(store: store)))),
    const Divider(height: 36),
    const Text('内容说明', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    const SizedBox(height: 10),
    const Text('首批 7 个单元、16 道变式，覆盖高数、数据结构与计算机网络。部分内容根据你旧对话中的疑问重新编写，具体来源附在每道例题后。'),
    const SizedBox(height: 12),
    const Text('支持手动录题、编辑关键点、经你同意后复制题目包分享。相关知识点仅按关键词匹配参考例题。共享题库、评论、点赞和纠错反馈需连接本机测试后台。支持本机照片文字识别，复杂公式和图形仍需核对。'),
    const SizedBox(height: 12),
    const Text('复习采用首版间隔规则，参考作答与求助情况安排。点过答案不会被直接算作独立掌握。'),
    TextButton(onPressed: () => showLicensePage(context: context, applicationName: '蓝笔', applicationVersion: '0.7.0'), child: const Text('开源许可')),
  ];

  @override
  Widget build(BuildContext context) => tab>=5?Scaffold(
    appBar:AppBar(title:Text(tab==5?'学习与搜索':tab==6?'工具与设置':'例题与复习'),leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>setState(()=>tab=0))),
    body:ListView(padding:const EdgeInsets.all(20),children:tab==5?library():tab==6?mine():today())):
    StudioShell(store:store,open:(lesson)=>open(lesson),record:recordContent,library:()=>setState(()=>tab=5),settings:()=>setState(()=>tab=6),practice:studyCenter);

}

class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 13, color: Colors.black54));
}
class BlueBox extends StatelessWidget {
  final Widget child;
  const BlueBox({super.key, required this.child});
  @override Widget build(BuildContext context) => Container(width: double.infinity,
    padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: bluePaper, borderRadius: BorderRadius.circular(18)), child: child);
}
class Formula extends StatelessWidget {
  final String? value;
  const Formula(this.value, {super.key});
  @override Widget build(BuildContext context) => value == null ? const SizedBox.shrink() : Padding(
    padding: const EdgeInsets.symmetric(vertical: 24), child: SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: Math.tex(value!, textStyle: const TextStyle(fontSize: 22), onErrorFallback: (_) => SelectableText(value!))));
}

class LinkedText extends StatefulWidget {
  final String text;
  final void Function(String) onConcept;
  const LinkedText(this.text, {super.key, required this.onConcept});
  @override State<LinkedText> createState() => _LinkedTextState();
}
class _LinkedTextState extends State<LinkedText> {
  final List<TapGestureRecognizer> gestures = [];
  @override void dispose() { for (final g in gestures) {g.dispose();} super.dispose(); }
  @override Widget build(BuildContext context) {
    for (final g in gestures) {g.dispose();} gestures.clear();
    final spans = <InlineSpan>[]; var start = 0;
    for (final match in RegExp(r'\[\[([^|]+)\|([^\]]+)\]\]').allMatches(widget.text)) {
      spans.add(TextSpan(text: widget.text.substring(start, match.start)));
      final g = TapGestureRecognizer()..onTap = () => widget.onConcept(match.group(1)!);
      gestures.add(g);
      spans.add(TextSpan(text: match.group(2), recognizer: g, style: const TextStyle(color: inkBlue,
        decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)));
      start = match.end;
    }
    spans.add(TextSpan(text: widget.text.substring(start)));
    return Text.rich(TextSpan(children: spans));
  }
}

class LessonPage extends StatefulWidget {
  final StudyStore store;
  final Lesson lesson;
  final bool review;
  const LessonPage({super.key, required this.store, required this.lesson, this.review = false});
  @override State<LessonPage> createState() => _LessonPageState();
}
class _LessonPageState extends State<LessonPage> {
  int hints = 0, steps = 0, variant = 0;
  int? selected;
  bool practice = false, assisted = false, busy = false, recorded = false;
  String reason = '暂未判断';
  final scroll = ScrollController();
  Lesson get lesson => widget.store.lessons.where((lesson) => lesson.id == widget.lesson.id).firstOrNull ?? widget.lesson;
  Future<void> editQuestion() async {
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => QuestionEditor(store: widget.store, id: lesson.id)));
    if (!mounted) return;
    if (result == 'deleted') { Navigator.pop(context); return; }
    setState(() { hints = 0; steps = 0; });
  }
  @override void initState() {
    super.initState(); practice = widget.review && lesson.variants.isNotEmpty;
    if (practice) variant = widget.store.progress(lesson.id).attempts % lesson.variants.length;
  }
  @override void dispose() {scroll.dispose(); super.dispose();}
  void top() { if (scroll.hasClients) scroll.jumpTo(0); }
  void concept(String id) {
    setState(() => assisted = true);
    final data = lesson.concepts.where((c) => c['id'] == id).firstOrNull;
    if (data == null) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true,
      backgroundColor: paper, builder: (context) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Eyebrow('知识点'), const SizedBox(height: 10),
          Text(data['title'] as String, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16), Text(data['body'] as String), Formula(data['formula'] as String?),
          const SizedBox(height: 16), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('回到刚才的位置')),
        ]))));
  }
  void help() => setState(() {assisted = true; if (hints < lesson.hints.length) hints++;});
  void reveal() => setState(() {assisted = true; steps = widget.store.guided ? (steps + 1).clamp(0, lesson.steps.length) : lesson.steps.length;});

  List<Widget> example() => [
    Eyebrow('${lesson.subject} · ${lesson.chapter}'), const SizedBox(height: 12),
    Text(widget.store.guided ? lesson.title : '例题 · 独立思考', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
    const SizedBox(height: 20), Text(lesson.prompt), Formula(lesson.formula),
    if(lesson.data['custom']==true)...{'firstThought':'我的第一反应','errorReason':'错误原因','summary':'一句话总结'}.entries.where((e)=>(widget.store.questions[lesson.id]?[e.key] as String? ?? '').isNotEmpty).map((e)=>Padding(padding:const EdgeInsets.only(top:16),child:SelectableText('${e.value}\n${widget.store.questions[lesson.id]![e.key]}'))),
    if (hints > 0) ...[BlueBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('提示 $hints / ${lesson.hints.length}', style: const TextStyle(color: inkBlue)),
      const SizedBox(height: 8), Text(lesson.hints[hints - 1]),
    ])), const SizedBox(height: 16)],
    if (lesson.steps.isEmpty) ...[
      const Text('这道题的解析还没补上，可以先独立思考，再记录自己的解法。'),
      const SizedBox(height: 16), FilledButton(onPressed: editQuestion, child: const Text('补充解析与关键点')),
      const SizedBox(height: 16), blueSummary(lesson),
    ],
    if (steps == 0 && lesson.steps.isNotEmpty) ...[
      FilledButton(onPressed: widget.store.guided && hints < lesson.hints.length ? help : reveal, child: Text(widget.store.guided
        ? hints < lesson.hints.length ? '给我一点提示' : '查看解答' : '我做完了，核对解答')),
      if (widget.store.guided || lesson.hints.isNotEmpty) TextButton(onPressed: widget.store.guided ? reveal : help, child: Text(widget.store.guided ? '看解答' : '需要一点提示')),
      if (lesson.variants.isNotEmpty) TextButton(onPressed: () {setState(() => practice = true); top();}, child: const Text('直接试做变式 →')),
    ],
    if (steps > 0) ...[
      const Divider(height: 32), const Text('为什么这样想到', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      ...List.generate(steps, (i) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow('第 ${i+1} 步'), const SizedBox(height: 6), LinkedText(lesson.steps[i]['text'] as String, onConcept: concept), Formula(lesson.steps[i]['formula'] as String?),
      ]))),
      if (steps < lesson.steps.length) FilledButton(onPressed: reveal, child: const Text('展开下一步')),
      if (steps == lesson.steps.length) ...[
        blueSummary(lesson), const SizedBox(height: 18),
        FilledButton(onPressed: () => editNote(context, widget.store, lesson), child: const Text('写下我的蓝笔总结')),
        if (lesson.variants.isNotEmpty) TextButton(onPressed: () {setState(() => practice = true); top();}, child: const Text('试一道变式 →')),
      ],
    ],
    const SizedBox(height: 18), ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('内容来源', style: TextStyle(fontSize: 13)), children: [Text(lesson.data['source'] as String)]),
  ];

  Future<void> record(String rating) async {
    if (busy || recorded || selected == null) return;
    setState(() => busy = true);
    final v = lesson.variants[variant];
    try {
      await widget.store.attempt(lesson.id, variantId: v['id'] as String, rating: rating,
        assisted: assisted, correct: selected == v['answer'], reason: reason);
      if (mounted) setState(() => recorded = true);
    } catch (_) { if (mounted) message(context, '记录未保存，请重试'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  List<Widget> exercise() {
    final v = lesson.variants[variant];
    final correct = selected == v['answer'];
    return [
      Eyebrow('${v['kind']} · ${variant + 1} / ${lesson.variants.length}'), const SizedBox(height: 12),
      const Text('换个问题，\n还想得到吗？', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
      const SizedBox(height: 20), Text(v['prompt'] as String), Formula(v['formula'] as String?),
      const SizedBox(height: 16),
      ...List.generate((v['options'] as List).length, (i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.all(16), backgroundColor: selected == i ? bluePaper : Colors.white,
          side: BorderSide(color: selected == i ? inkBlue : const Color(0xffe0e1e5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: selected == null ? () => setState(() => selected = i) : null,
        child: Text('${String.fromCharCode(65+i)}   ${(v['options'] as List)[i]}', style: const TextStyle(color: Color(0xff252a34))),
      ))),
      if (selected == null && lesson.concepts.isNotEmpty) TextButton(onPressed: () {
        setState(() => assisted = true);
        concept(lesson.concepts.first['id'] as String);
      }, child: const Text('查看相关知识点')),
      if (selected != null) ...[
        const SizedBox(height: 14), BlueBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(correct ? '判断正确' : '这一步值得再看', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: inkBlue)),
          const SizedBox(height: 10), Text(v['explanation'] as String),
          if (assisted) const Padding(padding: EdgeInsets.only(top: 10), child: Text('本轮使用过提示或例题解答，会安排后续独立验证。', style: TextStyle(fontSize: 13))),
        ])),
        const SizedBox(height: 18),
        if (!recorded) ...[
          const Text('这次主要卡在哪里？', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10), Wrap(spacing: 6, children: ['暂未判断','没想到用','忘记了','条件理解错','计算出错','没有卡住'].map((r) => ChoiceChip(
            label: Text(r), selected: reason == r, onSelected: busy ? null : (_) => setState(() => reason = r))).toList()),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : () => record(correct ? 'good' : 'again'), child: Text(busy ? '正在保存…' : correct ? '完成本题，安排复习' : '记下卡点，稍后再练')),
          if (correct) TextButton(onPressed: busy ? null : () => record('hard'), child: const Text('这次有些勉强，提前复习')),
        ] else ...[
          Text('已保存 · ${dueLabel(widget.store.progress(lesson.id).due)}', style: const TextStyle(color: inkBlue)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () {setState(() {variant = (variant+1) % lesson.variants.length; selected = null; recorded = false; reason = '暂未判断';}); top();}, child: const Text('继续下一道变式')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('今天先到这里')),
        ],
        TextButton(onPressed: () => editNote(context, widget.store, lesson), child: const Text('补充我的蓝笔总结')),
      ],
    ];
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(practice ? '举一反三' : widget.store.guided ? '循序渐进' : '直接挑战'),
      actions: [PopupMenuButton<String>(tooltip: '更多学习工具', onSelected: (value) async {
        if (value == 'feedback') { await createFeedback(context, widget.store, lesson.id, lesson.title); }
        if (value == 'recall' && context.mounted) {
          setState(() => assisted = true);
          await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => RecallPage(store: widget.store, lesson: lesson)));
        }
        if (value == 'favorite') {
          try {
            await widget.store.setting('favorite:${lesson.id}', widget.store.settings['favorite:${lesson.id}'] == 'true' ? 'false' : 'true');
            if (mounted) setState(() {});
          } catch (_) { if (context.mounted) message(context, '收藏未保存，请重试'); }
        }
      }, itemBuilder: (_) => [
        PopupMenuItem(value: 'favorite', child: Text(widget.store.settings['favorite:${lesson.id}'] == 'true' ? '取消收藏' : '收藏这道题')),
        const PopupMenuItem(value: 'recall', child: Text('关键点回想')),
        const PopupMenuItem(value: 'feedback', child: Text('纠错反馈')),
      ]), if (lesson.data['custom'] == true) ...[
        IconButton(tooltip: '编辑题目', icon: const Icon(Icons.edit_outlined), onPressed: editQuestion),
        IconButton(tooltip: '分享题目包', icon: const Icon(Icons.share_outlined), onPressed: () => shareQuestionDialog(context, widget.store, lesson.id)),
      ], IconButton(tooltip: '蓝笔总结', icon: const Icon(Icons.edit_note), onPressed: () {
        setState(() => assisted = true); editNote(context, widget.store, lesson);
      })]),
    body: SafeArea(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(24, 16, 24, 36), children: practice ? exercise() : example())))),
  );
}

String dueLabel(DateTime? date) {
  if (date == null) return '尚未安排复习';
  if (date.isBefore(DateTime.now())) return '现在可以复习';
  return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')} 复习';
}

Widget blueSummary(Lesson lesson) => BlueBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  const Text('这一题的蓝笔', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: inkBlue)),
  ...{'trigger':'看到什么','action':'想到哪一步','conditions':'使用条件','pitfall':'容易误用的地方'}.entries.map((e) => Padding(
    padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.value, style: const TextStyle(color: inkBlue, fontSize: 13)), Text(lesson.blue[e.key] as String),
    ]))),
]));

Future<void> editNote(BuildContext context, StudyStore store, Lesson lesson) async {
  final controller = TextEditingController(text: store.progress(lesson.id).note ?? lesson.blue['trigger'] as String);
  bool saving = false;
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, backgroundColor: paper,
    builder: (context) => StatefulBuilder(builder: (context, setState) => SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(lesson.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10), const Text('用自己的话记下：看到什么，就想到什么。'),
        const SizedBox(height: 16), TextField(controller: controller, minLines: 4, maxLines: 8, maxLength: 18000,
          decoration: const InputDecoration(labelText: '我的蓝笔总结', alignLabelWithHint: true)),
        const SizedBox(height: 12), FilledButton(onPressed: saving ? null : () async {
          setState(() => saving = true);
          try { await store.note(lesson.id, controller.text); if (context.mounted) Navigator.pop(context); }
          catch (_) {if(context.mounted) {setState(() => saving = false); message(context,'笔记未保存，请重试');}}
        }, child: Text(saving ? '正在保存…' : '保存笔记')),
        if (store.progress(lesson.id).noteHistory.length > 1) ExpansionTile(title: const Text('查看旧版本'), children:
          store.progress(lesson.id).noteHistory.reversed.skip(1).take(10).map((e) => ListTile(title: Text(e.payload['text'] as String),
            subtitle: Text(DateTime.fromMillisecondsSinceEpoch(e.at).toString().substring(0,16)),
            onTap: () => controller.text = e.payload['text'] as String)).toList()),
      ])))));
  // The bottom-sheet closing animation may still reference the controller.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  controller.dispose();
}

Future<void> backupDialog(BuildContext context, StudyStore store) async {
  final backup = store.backup();
  await showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('导出备份'), content: Text('共 ${store.events.length} 条记录。复制后保存到自己的文本文件；恢复时粘贴即可。备份包含笔记和作答历史，不含同步口令。'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      TextButton(onPressed: () async {await Clipboard.setData(ClipboardData(text: backup)); if(context.mounted) {Navigator.pop(context); message(context,'备份已复制，请粘贴到安全位置保存');}}, child: const Text('复制备份'))],
  ));
}

Future<void> importDialog(BuildContext context, StudyStore store) async {
  final controller = TextEditingController();
  bool busy = false;
  String? error;
  await showDialog<void>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
    title: const Text('恢复备份'), content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('将备份文本粘贴在这里。导入会合并历史，不清空现有记录。'), const SizedBox(height: 12),
      TextField(controller: controller, minLines: 4, maxLines: 6, decoration: InputDecoration(hintText: '粘贴蓝笔备份', errorText: error)),
    ])), actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('取消')),
      TextButton(onPressed: busy ? null : () async {
        setState(() {busy = true; error = null;});
        try {final count = await store.restore(controller.text); if(context.mounted) {Navigator.pop(context); message(context,'已合并 $count 条新记录');}}
        catch (_) {if(context.mounted) setState(() {busy=false; error='备份无效或包含冲突，原记录未被覆盖';});}
      }, child: Text(busy ? '正在导入…' : '合并恢复'))],
  )));
  await Future<void>.delayed(const Duration(milliseconds: 350)); controller.dispose();
}

class SyncPage extends StatefulWidget {
  final StudyStore store;
  const SyncPage({super.key, required this.store});
  @override State<SyncPage> createState() => _SyncPageState();
}
class _SyncPageState extends State<SyncPage> {
  late final address = TextEditingController(text: widget.store.settings['syncUrl'] ?? '');
  final token = TextEditingController();
  bool busy = false;
  String status = '尚未同步';
  @override void dispose() {address.dispose();token.dispose();super.dispose();}
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('跨设备同步')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('同一份学习，\n在不同设备接着走。', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16), const Text('连接你自己运行的同步服务。两台设备填入相同的地址和口令，分别点击同步。首版仅供个人使用，不含公共账号注册。'),
      const SizedBox(height: 24), TextField(controller: address, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: '服务地址', hintText: 'https://你的服务地址')),
      const SizedBox(height: 16), TextField(controller: token, obscureText: true, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(labelText: '同步口令', helperText: '至少 32 个字符；离开此页后不保存口令')),
      const SizedBox(height: 20), FilledButton(onPressed: busy ? null : () async {
        FocusScope.of(context).unfocus(); setState(() {busy=true;status='正在同步…';});
        try {final added=await widget.store.sync(address.text,token.text); if(mounted) setState(() => status='同步完成，合并 $added 条新记录');}
        catch (e) {if(mounted) setState(() => status=e is FormatException ? e.message : '同步失败，请检查服务地址、口令与网络。离线记录仍在本机。');}
        finally {if(mounted) setState(() => busy=false);}
      }, child: Text(busy?'同步中…':'立即同步')),
      const SizedBox(height: 12), Text(status, style: const TextStyle(color: inkBlue)),
      const SizedBox(height: 24), const Text('同步服务需要 HTTPS 地址与有效证书。当前没有默认云端地址，也不会自动上传笔记；尚未配置服务时，可用备份在设备间迁移。'),
    ])));
}
