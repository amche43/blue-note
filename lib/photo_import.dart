import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'community.dart';
import 'store.dart';
import 'brand.dart';
import 'domain.dart';
import 'question_photos.dart';

class PhotoImportPage extends StatefulWidget {
  final StudyStore store;
  final bool answer;
  const PhotoImportPage({super.key, required this.store, this.answer = false});
  @override
  State<PhotoImportPage> createState() => _PhotoImportPageState();
}

class _PhotoImportPageState extends State<PhotoImportPage> {
  Uint8List? photo;
  Json? rawResult;
  final text = TextEditingController();
  bool consent = false, checked = false, busy = false;
  String error = '', notice = '';
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> choose(String method) async {
    setState(() => busy = true);
    try {
      final result = await const MethodChannel(
        'blue_note/photo',
      ).invokeMethod<Uint8List>(method);
      if (result != null && mounted) {
        setState(() {
          photo = result;
          rawResult = null;
          text.clear();
          notice = '';
          error = '';
          checked = false;
          consent = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? e.message ?? '无法打开图片'
              : '当前设备暂不支持照片选择',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recognize() async {
    setState(() {
      busy = true;
      error = '';
      checked = false;
    });
    try {
      final config = widget.store.settings['community'];
      if (config == null) {
        throw const FormatException('请先在“我的 → 设置 → 登录 / 注册”连接本机后台');
      }
      final result = await CommunityClient(CommunityClient.parse(config))
          .request('POST', '/v1/ocr', {
            'consent': true,
            'image': base64Encode(photo!),
          });
      if (mounted) {
        setState(() {
          rawResult = result;
          text.text = result['text'] as String;
          notice = result['notice'] as String;
          if (text.text.isEmpty) {
            error = '未识别到文字，请换清晰照片或手动填写';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : '识别没有完成，请稍后重试。原图仍保留在此页。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.answer ? '添加答案照片' : '添加题目照片')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (photo == null && !busy)
          const Center(child: SceneMascot(MascotScene.capture, width: 140)),
        const Text('尽量只拍一道题，保留完整条件和图表。识别由你连接的电脑完成，不自动公开，也不自动生成答案。'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => choose('camera'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍照'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => choose('pick'),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('相册'),
              ),
            ),
          ],
        ),
        if (photo != null) ...[
          Image.memory(photo!, height: 260, fit: BoxFit.contain),
          FilledButton.icon(
            icon: const Icon(Icons.photo_outlined),
            label: const Text('直接使用照片，不识别'),
            onPressed: busy
                ? null
                : () {
                    try {
                      final encoded = validatePhoto(base64Encode(photo!));
                      Navigator.pop(context, <String, dynamic>{
                        'text': '',
                        'photo': encoded,
                        'title': '',
                        'capture': {
                          'source_image': encoded,
                          'ocr_raw': null,
                          'ai_parsed': null,
                          'source_type': 'photo',
                        },
                      });
                    } catch (_) {
                      setState(() => error = '照片过大，请裁剪后重试');
                    }
                  },
          ),
          CheckboxListTile(
            value: consent,
            onChanged: busy
                ? null
                : (v) => setState(() => consent = v ?? false),
            title: const Text('同意将这张照片发送到当前本机后台识别'),
          ),
          FilledButton(
            onPressed: busy || !consent ? null : recognize,
            child: Text(busy ? '正在处理…' : '识别题目文字'),
          ),
        ],
        if (busy) ...[
          const Center(child: SceneMascot(MascotScene.capture, width: 110)),
          const Text('蓝笔正在读取文字，请稍等…'),
          const LinearProgressIndicator(),
        ],
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (notice.isNotEmpty) Text(notice),
        const SizedBox(height: 16),
        TextField(
          controller: text,
          maxLines: 12,
          maxLength: 18000,
          enabled: !busy,
          onChanged: (_) => setState(() => checked = false),
          decoration: InputDecoration(
            labelText: widget.answer ? '答案识别草稿，请核对' : '识别草稿，可对照照片修改',
          ),
        ),
        CheckboxListTile(
          value: checked,
          onChanged: busy ? null : (v) => setState(() => checked = v ?? false),
          title: const Text('已核对题目条件、符号与上下标'),
        ),
        FilledButton(
          onPressed: busy || !checked || text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                  'text': text.text.trim(),
                  'title': '',
                  'photo': '',
                  'capture': {
                    'source_image': photo == null ? null : base64Encode(photo!),
                    'ocr_raw': rawResult,
                    'ai_parsed': null,
                    'ai_status': '未配置结构化模型',
                    'confirmed_at': DateTime.now().toIso8601String(),
                  },
                }),
          child: const Text('填入题干，继续编辑'),
        ),
        const Text(
          '直接使用的照片是正式内容，作者确认公开时会一起分享；电子版识别原图仅作私人核对记录。复杂公式与手写内容需人工核对。',
          style: TextStyle(fontSize: 13),
        ),
      ],
    ),
  );
}
