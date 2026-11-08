import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../services/field_detection/field_kind.dart';
import '../../profile/profile_model.dart';
import 'autofill.dart';

/// Anteprima dei campi trovati: niente viene inserito senza conferma.
/// Restituisce le proposte confermate, oppure null se l'utente annulla.
class AutofillPreviewPage extends StatefulWidget {
  const AutofillPreviewPage({
    super.key,
    required this.proposals,
    required this.hasSignature,
    this.note,
    this.profiles = const [],
    this.initialProfileId,
    this.today = '',
  });

  final List<FillProposal> proposals;
  final bool hasSignature;

  /// Messaggio informativo in testa (es. motore usato).
  final String? note;

  /// Profili tra cui scegliere (se più di uno compare il selettore).
  final List<NamedProfile> profiles;
  final String? initialProfileId;
  final String today;

  @override
  State<AutofillPreviewPage> createState() => _AutofillPreviewPageState();
}

class _AutofillPreviewPageState extends State<AutofillPreviewPage> {
  late final _ctrls = [for (final p in widget.proposals) TextEditingController(text: p.value)];
  late String? _profileId = widget.initialProfileId;

  /// Ricalcola i valori proposti con un altro profilo.
  void _useProfile(String id) {
    final np = widget.profiles.where((p) => p.id == id).firstOrNull;
    if (np == null) return;
    setState(() {
      _profileId = id;
      for (var i = 0; i < widget.proposals.length; i++) {
        final pr = widget.proposals[i];
        if (pr.isSignature || pr.isChoice) continue;
        final v = pr.field.kind.proposedValue(np.profile, today: widget.today);
        pr.value = v;
        pr.include = v.isNotEmpty;
        _ctrls[i].text = v;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  int get _count => widget.proposals.where((p) => p.include && (p.isSignature ? widget.hasSignature : p.value.trim().isNotEmpty)).length;

  void _confirm() {
    for (var i = 0; i < widget.proposals.length; i++) {
      widget.proposals[i].value = _ctrls[i].text;
    }
    Navigator.of(context).pop(widget.proposals.where((p) => p.include).toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final n = _count;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Annulla', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('Campi trovati'),
      ),
      body: PageFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Controlla i valori proposti. Togli la spunta ai campi che non vuoi compilare.',
              style: TextStyle(color: c.secondary),
            ),
            if (widget.profiles.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Compila con'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _profileId,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [for (final p in widget.profiles) DropdownMenuItem(value: p.id, child: Text(p.label))],
                      onChanged: (v) => v == null ? null : _useProfile(v),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.note != null) ...[
              const SizedBox(height: 6),
              Text(widget.note!, style: TextStyle(color: c.secondary, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            for (var i = 0; i < widget.proposals.length; i++) _tile(i),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: n == 0 ? null : _confirm,
            child: Text(n == 1 ? 'Inserisci 1 campo' : 'Inserisci $n campi'),
          ),
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final c = AppColors.of(context);
    final p = widget.proposals[i];
    final f = p.field;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: p.include,
                onChanged: (v) => setState(() => p.include = v ?? false),
                semanticLabel: 'Compila ${f.kind.label}',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text(f.kind.label, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '"${f.label}" · pagina ${f.page + 1}${f.source == 'AI' ? ' · AI' : ''}',
                      style: TextStyle(color: c.secondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (p.isChoice)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final o in [...f.options.map((o) => o.label), ''])
                            ChoiceChip(
                              label: Text(o.isEmpty ? 'Nessuna' : o),
                              selected: p.value == o,
                              onSelected: (_) => setState(() {
                                p.value = o;
                                p.include = o.isNotEmpty;
                              }),
                            ),
                        ],
                      )
                    else if (p.isSignature)
                      Text(
                        widget.hasSignature ? 'Verrà inserita la firma predefinita.' : 'Nessuna firma salvata: crea una firma per inserirla.',
                        style: TextStyle(color: widget.hasSignature ? c.ink : c.danger),
                      )
                    else
                      TextField(
                        controller: _ctrls[i],
                        enabled: p.include,
                        decoration: InputDecoration(
                          labelText: 'Valore',
                          hintText: f.kind == FieldKind.text ? null : 'Manca nel profilo',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() {
                          p.value = v;
                          if (v.trim().isNotEmpty) p.include = true;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
