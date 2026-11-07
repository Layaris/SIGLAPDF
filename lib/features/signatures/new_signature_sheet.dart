import 'package:flutter/material.dart';

import 'drawing/draw_signature_page.dart';
import 'signature_model.dart';

/// Scelta del tipo (firma o sigla) e del metodo di creazione.
Future<void> showNewSignatureSheet(BuildContext context, {SignatureKind initialKind = SignatureKind.signature}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NewSignatureSheet(initialKind: initialKind, parentContext: context),
  );
}

class _NewSignatureSheet extends StatefulWidget {
  const _NewSignatureSheet({required this.initialKind, required this.parentContext});
  final SignatureKind initialKind;
  final BuildContext parentContext;

  @override
  State<_NewSignatureSheet> createState() => _NewSignatureSheetState();
}

class _NewSignatureSheetState extends State<_NewSignatureSheet> {
  late SignatureKind _kind = widget.initialKind;

  void _open(Widget page) {
    final nav = Navigator.of(widget.parentContext);
    Navigator.of(context).pop();
    nav.push(MaterialPageRoute<bool>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nuova', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<SignatureKind>(
              segments: const [
                ButtonSegment(value: SignatureKind.signature, label: Text('Firma'), icon: Icon(Icons.gesture)),
                ButtonSegment(value: SignatureKind.initials, label: Text('Sigla'), icon: Icon(Icons.short_text)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Disegna'),
              subtitle: const Text('Con il dito, lo stilo o il mouse'),
              onTap: () => _open(DrawSignaturePage(kind: _kind)),
            ),
          ],
        ),
      ),
    );
  }
}
