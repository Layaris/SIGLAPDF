import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../signature_model.dart';

/// Chiede il nome della firma. Restituisce null se l'utente annulla.
Future<String?> showSaveSignatureDialog(
  BuildContext context, {
  required SignatureKind kind,
  required int existingCount,
  String? initial,
  String? title,
}) {
  final suggested = initial ?? (existingCount == 0 ? kind.label : '${kind.label} ${existingCount + 1}');
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title ?? tr('Dai un nome'), initial: suggested),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Nome')),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Annulla'))),
          FilledButton(onPressed: _ok, child: Text(tr('Salva'))),
        ],
      );
}
