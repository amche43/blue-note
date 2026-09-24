import 'package:flutter/material.dart';
import 'domain.dart';
import 'store.dart';
import 'ink_page.dart';

// Preserve old route signatures without the retired multi-field form.
class EntryComposer extends StatelessWidget {
  final StudyStore store;
  final String initialKind;
  final Json? initialCapture;
  const EntryComposer({
    super.key,
    required this.store,
    this.initialKind = 'question',
    this.initialCapture,
  });
  @override
  Widget build(BuildContext context) => InkPage(
    store: store,
    initial: initialCapture == null
        ? null
        : {
            'prompt': initialCapture!['text'] as String? ?? '',
            'contentKind': initialKind,
          },
  );
}
