import 'package:flutter/material.dart';

/// Swiping reveals an action; it never deletes the row by itself.
class SwipeDelete extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDelete, onUpload;
  const SwipeDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.onUpload,
  });
  @override
  State<SwipeDelete> createState() => _SwipeDeleteState();
}

class _SwipeDeleteState extends State<SwipeDelete> {
  double reveal = 0;
  double get extent => widget.onUpload == null ? 80 : 160;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: reveal,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: extent,
              maxWidth: extent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.onUpload != null)
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff2878f0),
                          shape: const RoundedRectangleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: reveal == 0
                            ? null
                            : () {
                                setState(() => reveal = 0);
                                widget.onUpload!();
                              },
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Icon(Icons.upload_rounded), Text('上传')],
                        ),
                      ),
                    ),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xffd83a49),
                        shape: const RoundedRectangleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: reveal == 0
                          ? null
                          : () {
                              setState(() => reveal = 0);
                              widget.onDelete?.call();
                            },
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.delete_outline), Text('删除')],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: widget.onDelete == null
              ? null
              : (d) => setState(
                  () => reveal = (reveal - d.delta.dx).clamp(0, extent),
                ),
          onHorizontalDragEnd: (_) =>
              setState(() => reveal = reveal > 25 ? extent : 0),
          child: Transform.translate(
            offset: Offset(-reveal, 0),
            child: Material(color: Colors.transparent, child: widget.child),
          ),
        ),
      ],
    ),
  );
}
