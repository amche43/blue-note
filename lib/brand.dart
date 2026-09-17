import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Display exact source pixels through a crop window; keep supplied sheets intact.
class BrandCrop extends StatelessWidget {
  final String sheet;
  final Rect region;
  final double width;
  final double sourceWidth, sourceHeight;
  const BrandCrop({
    super.key,
    required this.sheet,
    required this.region,
    this.width = 64,
    this.sourceWidth = 1448,
    this.sourceHeight = 1086,
  });
  @override
  Widget build(BuildContext context) {
    final scale = width / region.width;
    return SizedBox(
      width: width,
      height: region.height * scale,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -region.left * scale,
              top: -region.top * scale,
              width: sourceWidth * scale,
              height: sourceHeight * scale,
              child: Image.asset(
                'assets/brand/$sheet.png',
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MascotScene { explore, capture, messages }

class SceneMascot extends StatelessWidget {
  final MascotScene scene;
  final double width;
  const SceneMascot(this.scene, {super.key, this.width = 150});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/mascot-${scene.name}.png',
    width: width,
    height: width,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
  );
}

class BlueMascot extends StatelessWidget {
  final double width;
  const BlueMascot({super.key, this.width = 100});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/mascot-transparent.png',
    width: width,
    height: width * 1.2,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}

final _avatarMemory = <String, Uint8List>{};
Uint8List avatarPhotoBytes(String data) {
  final cached = _avatarMemory[data];
  if (cached != null) return cached;
  final decoded = base64Decode(data);
  if (_avatarMemory.length >= 64) {
    _avatarMemory.remove(_avatarMemory.keys.first);
  }
  _avatarMemory[data] = decoded;
  return decoded;
}

class BlueAvatar extends StatelessWidget {
  final int index;
  final double width;
  final String? photo;
  const BlueAvatar({super.key, this.index = 0, this.width = 42, this.photo});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: width,
    child: ClipOval(
      child: photo != null && photo!.isNotEmpty
          ? Image.memory(
              avatarPhotoBytes(photo!),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  BlueAvatar(index: index, width: width),
            )
          : FittedBox(
              fit: BoxFit.cover,
              child: BrandCrop(
                sheet: 'avatars',
                region: Rect.fromLTWH(
                  33 + (index % 8) * 174,
                  index >= 8 ? 558 : 312,
                  162,
                  191,
                ),
                width: width,
              ),
            ),
    ),
  );
}

class SubjectArt extends StatelessWidget {
  final String subject;
  const SubjectArt(this.subject, {super.key});
  @override
  Widget build(BuildContext context) {
    final icon =
        <String, IconData>{
          '高等数学': Icons.functions,
          '线性代数': Icons.grid_4x4,
          '概率论': Icons.stacked_line_chart,
          '数据结构': Icons.account_tree_outlined,
          '计算机网络': Icons.language,
          '计算机组成原理': Icons.memory,
          '操作系统': Icons.layers_outlined,
          '英语': Icons.translate,
          '物理': Icons.science_outlined,
        }[subject] ??
        Icons.menu_book_rounded;
    return SizedBox.square(
      dimension: 40,
      child: Icon(icon, size: 29, color: const Color(0xff2878f0)),
    );
  }
}

const stickerNames = [
  '开心',
  '点赞',
  '加油',
  '疑问',
  '思考',
  '惊讶',
  '委屈',
  '无语',
  '睡觉',
  '庆祝',
  '收到',
  '太棒了',
  '一起冲',
  '这题咋做',
  '我想想',
  '震惊',
  '委屈巴巴',
  '无语住了',
  '困了',
  '拿下',
];

class BlueSticker extends StatelessWidget {
  final int index;
  final double width;
  const BlueSticker(this.index, {super.key, this.width = 72});
  @override
  Widget build(BuildContext context) => BrandCrop(
    sheet: 'stickers',
    region: index < 10
        ? Rect.fromLTWH(31 + index * 137, 365, 130, 126)
        : Rect.fromLTWH(
            34 + ((index - 10) % 5) * 142,
            index < 15 ? 588 : 738,
            137,
            126,
          ),
    width: width,
  );
}

const avatarNames = [
  '蓝笔',
  '笔记本',
  '橡皮擦',
  '小尺',
  '圆珠笔',
  '荧光笔',
  '回形针',
  '便利贴',
  '闪光蓝笔',
  '音乐蓝笔',
  '阅读蓝笔',
  '毕业蓝笔',
  '爱心笔记本',
  '思考橡皮',
  '博学小尺',
  '猫咪便利贴',
];
Future<int?> chooseBlueAvatar(BuildContext context, int selected) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择你的学习伙伴',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                '同一个学习旅程，不同的可爱陪伴。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 8,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: .78,
                ),
                itemBuilder: (_, i) => Semantics(
                  selected: selected == i,
                  button: true,
                  label: avatarNames[i],
                  child: InkWell(
                    key: ValueKey('avatar-choice-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, i),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected == i
                                  ? const Color(0xff2878f0)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: BlueAvatar(index: i, width: 42),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          avatarNames[i],
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('avatar-custom'),
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('自定义头像'),
                subtitle: const Text('上传照片，审核通过后使用'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, -1),
              ),
            ],
          ),
        ),
      ),
    );
Future<String?> chooseBlueSticker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Icon(Icons.emoji_emotions_outlined, color: Color(0xff2878f0)),
                  SizedBox(width: 8),
                  Text(
                    '蓝笔表情',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: stickerNames.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisExtent: 100,
                ),
                itemBuilder: (_, i) => InkWell(
                  key: ValueKey('sticker-choice-$i'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, '[蓝笔表情:${stickerNames[i]}]'),
                  child: Column(
                    children: [
                      BlueSticker(i, width: 64),
                      Text(
                        stickerNames[i],
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

class BlueMessageBody extends StatelessWidget {
  final String text;
  const BlueMessageBody(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: text.split('\n').where((s) => s.isNotEmpty).map((line) {
      final index = stickerNames.indexWhere((name) => line == '[蓝笔表情:$name]');
      return index < 0
          ? SelectableText(line)
          : Semantics(
              label: stickerNames[index],
              image: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BlueSticker(index, width: 96),
                ),
              ),
            );
    }).toList(),
  );
}
