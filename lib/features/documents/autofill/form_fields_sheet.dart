import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/pdf_service.dart';
import '../editor/editor_controller.dart';

/// Pannello dei campi AcroForm del PDF: compilazione a mano o dal profilo.
Future<void> showFormFieldsSheet(
  BuildContext context, {
  required EditorController controller,
  required VoidCallback onAutofill,
  String? focusField,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormFieldsSheet(controller: controller, onAutofill: onAutofill, focusField: focusField),
    );

class _FormFieldsSheet extends StatefulWidget {
  const _FormFieldsSheet({required this.controller, required this.onAutofill, this.focusField});
  final EditorController controller;
  final VoidCallback onAutofill;
  final String? focusField;

  @override
  State<_FormFieldsSheet> createState() => _FormFieldsSheetState();
}

class _FormFieldsSheetState extends State<_FormFieldsSheet> {
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(FormFieldInfo f) {
    final ctrl = _text.putIfAbsent(f.name, () => TextEditingController(text: widget.controller.formValues[f.name] ?? ''));
    final v = widget.controller.formValues[f.name] ?? '';
    if (ctrl.text != v) ctrl.text = v; // aggiornato da autocompilazione o annulla
    return ctrl;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fields = widget.controller.info.fillableFields;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Campi del modulo', style: Theme.of(context).textTheme.titleLarge)),
                    TextButton.icon(
                      onPressed: widget.onAutofill,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Dal profilo'),
                    ),
                  ],
                ),
                Text('${fields.length} campi. Diventano testo fisso quando esporti il PDF.', style: TextStyle(color: c.secondary)),
                const SizedBox(height: 16),
                for (final f in fields) _field(f),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(FormFieldInfo f) {
    final value = widget.controller.formValues[f.name] ?? '';
    final label = f.page >= 0 ? '${f.name} · pag. ${f.page + 1}' : f.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (f.kind) {
        FormFieldKind.checkbox => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: value == 'true',
            onChanged: (v) => widget.controller.setFormValue(f.name, v ? 'true' : 'false'),
          ),
        FormFieldKind.combo || FormFieldKind.list || FormFieldKind.radio => DropdownButtonFormField<String>(
            initialValue: f.options.contains(value) ? value : null,
            decoration: InputDecoration(labelText: label),
            items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => widget.controller.setFormValue(f.name, v ?? ''),
          ),
        _ => TextField(
            controller: _ctrlFor(f),
            autofocus: widget.focusField == f.name,
            maxLines: f.multiline ? 3 : 1,
            decoration: InputDecoration(labelText: label),
            onChanged: (v) => widget.controller.setFormValue(f.name, v),
          ),
      },
    );
  }
}
