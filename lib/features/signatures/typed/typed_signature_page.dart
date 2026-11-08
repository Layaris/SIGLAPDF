import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../signature_model.dart';
import '../widgets/save_signature_dialog.dart';
import 'typed_renderer.dart';

/// Firma "scritta": testo digitato reso con un font corsivo.
class TypedSignaturePage extends StatefulWidget {
  const TypedSignaturePage({super.key, this.kind = SignatureKind.signature});

  final SignatureKind kind;

  @override
  State<TypedSignaturePage> createState() => _TypedSignaturePageState();
}

class _TypedSignaturePageState extends State<TypedSignaturePage> {
  final _ctrl = TextEditingController();
  late Color _color;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    _color = InkColors.fromName(services.settings.value.inkColor);
    if (_ctrl.text.isEmpty) {
      final p = services.profile.value;
      final suggestion = widget.kind == SignatureKind.initials ? p.initials : p.fullName;
      if (suggestion.isNotEmpty) _ctrl.text = suggestion;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty || _saving) return;
    final repo = AppScope.of(context).signatures;
    final name = await showSaveSignatureDialog(context, kind: widget.kind, existingCount: repo.ofKind(widget.kind).length);
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    final r = await renderTypedSignature(_ctrl.text, color: _color);
    if (r == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    await repo.add(name: name, kind: widget.kind, source: SignatureSource.typed, png: r.png, width: r.width, height: r.height);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isInitials = widget.kind == SignatureKind.initials;
    return Scaffold(
      appBar: AppBar(
        title: Text(isInitials ? tr('Scrivi la sigla') : tr('Scrivi la firma')),
        actions: [
          ListenableBuilder(
            listenable: _ctrl,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _ctrl.text.trim().isEmpty || _saving ? null : _save,
                child: Text(tr('Salva')),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _ctrl,
              autofocus: _ctrl.text.isEmpty,
              textCapitalization: TextCapitalization.words,
              maxLength: isInitials ? 6 : 40,
              decoration: InputDecoration(labelText: isInitials ? tr('Iniziali') : tr('Nome e cognome')),
            ),
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (context, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _ctrl.text.trim().isEmpty ? (isInitials ? 'M.R.' : tr('Mario Rossi')) : _ctrl.text.trim(),
                    style: TextStyle(
                      fontFamily: cursiveFontFamily,
                      fontSize: 64,
                      color: _ctrl.text.trim().isEmpty ? const Color(0xFFB8BEC8) : _color,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(tr('Colore'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Color>(
              segments: [
                ButtonSegment(value: InkColors.blue, label: Text(tr('Blu'))),
                ButtonSegment(value: InkColors.black, label: Text(tr('Nero'))),
              ],
              selected: {_color},
              onSelectionChanged: (s) => setState(() => _color = s.first),
            ),
          ],
        ),
      ),
    );
  }
}
