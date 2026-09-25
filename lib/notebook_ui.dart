import 'package:flutter/material.dart';

const notebookPaper = Color(0xfff3f9ff);
const notebookInk = Color(0xff101c45);
const notebookColors = [
  Color(0xff58a7fa),
  Color(0xff70ca8a),
  Color(0xff9877ef),
  Color(0xffffb85c),
  Color(0xff4fc6d6),
  Color(0xffec7dae),
];

class NotebookAddButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  const NotebookAddButton({
    super.key,
    required this.onPressed,
    this.tooltip = '添加',
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12, top: 5, bottom: 5),
    child: IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff1263ff),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        minimumSize: const Size(52, 52),
      ),
      icon: const Icon(Icons.add, size: 32),
    ),
  );
}

enum NoteIconState { local, published, readOnly, shared, pending }

enum NoteIconKind { book, chapter, page }

class NotebookCover extends StatelessWidget {
  final int index;
  final String? number;
  final NoteIconState state;
  final NoteIconKind? kind;
  final IconData? contentIcon;
  const NotebookCover({
    super.key,
    this.index = 0,
    this.number,
    this.state = NoteIconState.local,
    this.kind,
    this.contentIcon,
  });
  @override
  Widget build(BuildContext context) {
    final color = notebookColors[index % notebookColors.length];
    return SizedBox(
      width: 52,
      height: 54,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NoteOutline(
                kind ??
                    (number == null ? NoteIconKind.book : NoteIconKind.chapter),
                color,
                contentIcon != null,
              ),
            ),
          ),
          if (contentIcon != null)
            Positioned(
              left: 19,
              top: 24,
              child: Icon(contentIcon, color: color, size: 18),
            ),
          if (state != NoteIconState.local)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: state == NoteIconState.pending
                    ? const Icon(
                        Icons.circle,
                        size: 12,
                        color: Color(0xffff863c),
                      )
                    : Icon(
                        switch (state) {
                          NoteIconState.published => Icons.upload_rounded,
                          NoteIconState.readOnly => Icons.lock_outline,
                          _ => Icons.people_alt_rounded,
                        },
                        color: color,
                        size: 20,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteOutline extends CustomPainter {
  final NoteIconKind kind;
  final Color color;
  final bool customContent;
  _NoteOutline(this.kind, this.color, this.customContent);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 52, size.height / 54);
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (kind == NoteIconKind.page) {
      final path = Path()
        ..moveTo(13, 5)
        ..lineTo(32, 5)
        ..lineTo(43, 16)
        ..lineTo(43, 46)
        ..quadraticBezierTo(43, 49, 39, 49)
        ..lineTo(13, 49)
        ..quadraticBezierTo(9, 49, 9, 45)
        ..lineTo(9, 9)
        ..quadraticBezierTo(9, 5, 13, 5);
      canvas.drawPath(path, p);
      canvas.drawPath(
        Path()
          ..moveTo(32, 5)
          ..lineTo(32, 16)
          ..lineTo(43, 16),
        p,
      );
      if (!customContent) {
        canvas.drawLine(const Offset(18, 29), const Offset(33, 29), p);
        canvas.drawLine(const Offset(18, 37), const Offset(29, 37), p);
      }
    } else {
      if (kind == NoteIconKind.chapter) {
        canvas.drawPath(
          Path()
            ..moveTo(10, 17)
            ..lineTo(10, 10)
            ..quadraticBezierTo(10, 6, 15, 6)
            ..lineTo(24, 6)
            ..lineTo(29, 12)
            ..lineTo(35, 12),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 17, 42, 32),
            const Radius.circular(7),
          ),
          p,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(10, 5, 32, 44),
            const Radius.circular(7),
          ),
          p,
        );
        canvas.drawLine(const Offset(48, 15), const Offset(48, 28), p);
      }
      for (final y in kind == NoteIconKind.book ? [19.0, 29.0, 39.0] : [29.0]) {
        canvas.drawLine(Offset(3, y), Offset(10, y), p);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NoteOutline old) =>
      kind != old.kind ||
      color != old.color ||
      customContent != old.customContent;
}

class NotebookCard extends StatelessWidget {
  final Widget child;
  const NotebookCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final tile = child;
    final content = tile is ListTile
        ? ListTile(
            minTileHeight: 72,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 0,
            ),
            leading: tile.leading == null
                ? null
                : SizedBox(
                    width: 36,
                    height: 38,
                    child: FittedBox(child: tile.leading),
                  ),
            title: tile.title is Text
                ? Text(
                    (tile.title as Text).data ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: notebookInk,
                    ),
                  )
                : tile.title,
            subtitle: tile.subtitle == null
                ? null
                : DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: tile.subtitle!,
                  ),
            onTap: tile.onTap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          )
        : tile;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.white,
          highlightColor: Colors.white.withValues(alpha: .7),
        ),
        child: content,
      ),
    );
  }
}

class NotebookDock extends StatelessWidget {
  final bool notes;
  final VoidCallback onBooks, onNotes, onSearch;
  const NotebookDock({
    super.key,
    this.notes = false,
    required this.onBooks,
    required this.onNotes,
    required this.onSearch,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  for (final item in [
                    (false, Icons.menu_book_rounded, '笔记本', onBooks),
                    (true, Icons.sticky_note_2_outlined, '便笺', onNotes),
                  ])
                    Expanded(
                      child: TextButton(
                        onPressed: item.$4,
                        style: TextButton.styleFrom(
                          backgroundColor: notes == item.$1
                              ? const Color(0xffe4efff)
                              : Colors.transparent,
                          foregroundColor: notes == item.$1
                              ? const Color(0xff1263ff)
                              : Colors.blueGrey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.$2, size: 22),
                            Text(item.$3, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 28),
          IconButton.filledTonal(
            onPressed: onSearch,
            tooltip: '搜索',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xff1263ff),
              minimumSize: const Size(54, 54),
            ),
            icon: const Icon(Icons.search, size: 28),
          ),
        ],
      ),
    ),
  );
}

String notebookUpdated(int at) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
  if (d.inMinutes < 1) return '刚刚更新';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前更新';
  if (d.inDays < 1) return '${d.inHours} 小时前更新';
  return '${d.inDays} 天前更新';
}

Future<String?> requestItemName(BuildContext context, String fallback) async {
  final controller = TextEditingController(text: fallback)
    ..selection = TextSelection(baseOffset: 0, extentOffset: fallback.length);
  final route = DialogRoute<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('输入名称'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) =>
            Navigator.pop(ctx, v.trim().isEmpty ? fallback : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('使用默认名称'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            controller.text.trim().isEmpty ? fallback : controller.text.trim(),
          ),
          child: const Text('完成'),
        ),
      ],
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  controller.dispose();
  return result;
}
