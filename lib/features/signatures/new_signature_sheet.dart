import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import 'drawing/draw_signature_page.dart';
import 'import/import_signature_page.dart';
import 'signature_model.dart';
import 'typed/typed_signature_page.dart';

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
            Text(tr('Nuova'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<SignatureKind>(
              segments: [
                ButtonSegment(value: SignatureKind.signature, label: Text(tr('Firma')), icon: const Icon(Icons.gesture)),
                const ButtonSegment(value: SignatureKind.initials, label: Text('Sigla'), icon: Icon(Icons.short_text)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text(tr('Disegna')),
              subtitle: Text(tr('Con il dito, lo stilo o il mouse')),
              onTap: () => _open(DrawSignaturePage(kind: _kind)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Importa da foto')),
              subtitle: Text(tr('Lo sfondo viene tolto in automatico')),
              onTap: () => _open(ImportSignaturePage(kind: _kind, origin: ImageOrigin.gallery)),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(tr('Scatta una foto')),
                subtitle: Text(tr('Firma su carta bianca e fotografa')),
                onTap: () => _open(ImportSignaturePage(kind: _kind, origin: ImageOrigin.camera)),
              ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(tr('Importa da file')),
              subtitle: Text(tr('JPG o PNG')),
              onTap: () => _open(ImportSignaturePage(kind: _kind, origin: ImageOrigin.file)),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(tr('Scrivi')),
              subtitle: Text(tr('Il tuo nome in corsivo')),
              onTap: () => _open(TypedSignaturePage(kind: _kind)),
            ),
          ],
        ),
      ),
    );
  }
}
