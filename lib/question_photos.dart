import 'dart:convert';
import 'package:flutter/material.dart';

const photoLimit = 4 * 1024 * 1024;
String validatePhoto(String value) {
  if (value.isEmpty) return value;
  if (value.length > photoLimit) throw const FormatException('单张照片过大，请裁剪后重试');
  final bytes = base64Decode(value);
  final png =
      bytes.length > 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71;
  final jpg =
      bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
  if (!png && !jpg) throw const FormatException('照片需要 JPEG 或 PNG 格式');
  return value;
}

class QuestionPhoto extends StatelessWidget {
  final String encoded, label;
  const QuestionPhoto(this.encoded, {super.key, this.label = '题目照片'});
  @override
  Widget build(BuildContext context) {
    if (encoded.isEmpty) return const SizedBox();
    final bytes = base64Decode(encoded);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · 点击放大',
            style: const TextStyle(color: Color(0xff2878f0)),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(label)),
                  body: Center(
                    child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 6,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            child: Image.memory(
              bytes,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) => const Text('照片暂时无法显示，请重新选择'),
            ),
          ),
        ],
      ),
    );
  }
}
