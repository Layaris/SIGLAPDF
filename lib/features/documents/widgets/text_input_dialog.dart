import 'package:flutter/material.dart';

/// Chiede un testo breve. Null se annullato o vuoto.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Testo',
  String action = 'Inserisci',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, label: label, action: action),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.label, required this.action});
  final String title;
  final String initial;
  final String label;
  final String action;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _c.text.trim();
    Navigator.of(context).pop(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _c,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
          FilledButton(onPressed: _ok, child: Text(widget.action)),
        ],
      );
}
