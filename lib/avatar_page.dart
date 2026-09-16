import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'brand.dart';
import 'community.dart';
import 'domain.dart';
import 'store.dart';

Rect avatarCropRect(int width, int height, double zoom, double x, double y) {
  final side = math.min(width, height) / zoom;
  return Rect.fromLTWH(
    (width - side) * (x + 1) / 2,
    (height - side) * (y + 1) / 2,
    side,
    side,
  );
}

class AvatarCropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  AvatarCropPainter(this.image, this.crop);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    crop,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.high,
  );
  @override
  bool shouldRepaint(AvatarCropPainter old) =>
      old.image != image || old.crop != crop;
}

class AvatarPage extends StatefulWidget {
  final StudyStore store;
  final CommunityClient? client;
  const AvatarPage({super.key, required this.store, this.client});
  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  CommunityClient? client;
  Json? status;
  ui.Image? photo;
  double zoom = 1, x = 0, y = 0;
  bool busy = false, consent = false;
  String error = '', rid = newId();
  @override
  void initState() {
    super.initState();
    client = widget.client;
    try {
      final raw = widget.store.settings['community'];
      if (client == null && raw != null) {
        client = CommunityClient(CommunityClient.parse(raw));
      }
    } catch (_) {}
    if (client != null) run(refresh);
  }

  @override
  void dispose() {
    photo?.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is PlatformException
              ? e.message ?? '无法选择照片'
              : '操作未确认完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final result = await client!.request('GET', '/v1/me/avatar');
    await widget.store.setting(
      'avatarImage',
      result['activeImage'] as String? ?? '',
    );
    if (mounted) setState(() => status = result['request'] as Json?);
  }

  Future<void> choosePhoto() async {
    final bytes = await const MethodChannel(
      'blue_note/photo',
    ).invokeMethod<Uint8List>('pick');
    if (bytes == null) return;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    final old = photo;
    setState(() {
      photo = frame.image;
      zoom = 1;
      x = 0;
      y = 0;
      consent = false;
      rid = newId();
    });
    old?.dispose();
  }

  Future<void> submit() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    AvatarCropPainter(
      photo!,
      avatarCropRect(photo!.width, photo!.height, zoom, x, y),
    ).paint(canvas, const Size(256, 256));
    final picture = recorder.endRecording();
    final output = await picture.toImage(256, 256);
    picture.dispose();
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    output.dispose();
    await client!.request('POST', '/v1/me/avatar', {
      'requestId': rid,
      'consent': true,
      'image': base64Encode(bytes!.buffer.asUint8List()),
    });
    if (mounted) {
      final old = photo;
      setState(() => photo = null);
      old?.dispose();
    }
    await refresh();
  }

  Future<void> defaultAvatar() async {
    final chosen = await chooseBlueAvatar(
      context,
      int.tryParse(widget.store.settings['avatar'] ?? '0') ?? 0,
    );
    if (chosen == null || !mounted) return;
    if (chosen == -1) {
      await run(choosePhoto);
      return;
    }
    await run(() async {
      if (client != null) {
        final me = await client!.request('GET', '/v1/me');
        await client!.request('PUT', '/v1/me', {
          'name': me['name'],
          'avatar': chosen,
          'useDefault': true,
        });
      }
      await widget.store.setting('avatar', '$chosen');
      await widget.store.setting('avatarImage', '');
      if (client != null) await refresh();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的头像'),
      actions: [
        IconButton(
          tooltip: '刷新审核状态',
          onPressed: busy || client == null ? null : () => run(refresh),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 12),
        Center(
          child: BlueAvatar(
            index: int.tryParse(widget.store.settings['avatar'] ?? '0') ?? 0,
            photo: widget.store.settings['avatarImage'],
            width: 90,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '当前使用的头像',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.blueGrey, fontSize: 12),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: busy ? null : defaultAvatar,
          icon: const Icon(Icons.face_outlined),
          label: const Text('选择默认吉祥物'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => run(choosePhoto),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('从相册上传照片'),
        ),
        const SizedBox(height: 12),
        const Text(
          '默认头像可直接使用。照片审核通过前，继续显示原头像。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
        if (client == null) const Text('上传审核前，请先在“我的 → 账号登录与注册”连接本机后台。'),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty)
          Text(error, style: const TextStyle(color: Colors.red)),
        if (status != null)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  {
                        'pending': '照片待审核',
                        'approved': '照片审核已通过',
                        'rejected': '照片未通过审核',
                        'cancelled': '申请已撤回',
                      }[status!['status']] ??
                      '审核状态',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (status!['reason'] != '') Text(status!['reason'] as String),
                if (status!['status'] == 'pending') ...[
                  const SizedBox(height: 12),
                  BlueAvatar(photo: status!['image'] as String?, width: 64),
                  const Text(
                    '仅你和审核者可见。',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await client!.request('DELETE', '/v1/me/avatar');
                            await refresh();
                          }),
                    child: const Text('撤回这次申请'),
                  ),
                ],
              ],
            ),
          ),
        if (photo != null) ...[
          const SizedBox(height: 18),
          const Text('调整照片位置', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Center(
            child: SizedBox.square(
              dimension: 220,
              child: ClipOval(
                child: CustomPaint(
                  painter: AvatarCropPainter(
                    photo!,
                    avatarCropRect(photo!.width, photo!.height, zoom, x, y),
                  ),
                ),
              ),
            ),
          ),
          const Text('缩放'),
          Slider(
            value: zoom,
            min: 1,
            max: 3,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    zoom = v;
                    rid = newId();
                  }),
          ),
          const Text('左右位置'),
          Slider(
            value: x,
            min: -1,
            max: 1,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    x = v;
                    rid = newId();
                  }),
          ),
          const Text('上下位置'),
          Slider(
            value: y,
            min: -1,
            max: 1,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    y = v;
                    rid = newId();
                  }),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: busy
                ? null
                : (v) => setState(() => consent = v ?? false),
            title: const Text(
              '提交给本机管理员审核，通过后作为公开头像',
              style: TextStyle(fontSize: 13),
            ),
          ),
          FilledButton(
            onPressed: busy || !consent || client == null
                ? null
                : () => run(submit),
            child: const Text('提交头像审核'),
          ),
        ],
      ],
    ),
  );
}
