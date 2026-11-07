import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/page_frame.dart';
import 'profile_model.dart';
import 'profile_repository.dart';

/// Profilo dati usato per compilare i moduli. Si salva da solo mentre scrivi.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ProfileRepository _repo;
  final Map<ProfileField, TextEditingController> _fields = {};
  final List<(TextEditingController, TextEditingController)> _custom = [];
  Timer? _debounce;
  bool _initialized = false;
  bool _savedHint = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).profile;
    final p = _repo.value;
    for (final f in ProfileField.values) {
      _fields[f] = TextEditingController(text: p[f]);
    }
    for (final c in p.custom) {
      _custom.add((TextEditingController(text: c.key), TextEditingController(text: c.value)));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveNow();
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final (k, v) in _custom) {
      k.dispose();
      v.dispose();
    }
    super.dispose();
  }

  Profile _collect() => Profile(
        values: {for (final e in _fields.entries) e.key: e.value.text.trim()},
        custom: [
          for (final (k, v) in _custom)
            if (k.text.trim().isNotEmpty) CustomField(k.text.trim(), v.text.trim()),
        ],
      );

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _saveNow();
      if (mounted) setState(() => _savedHint = true);
    });
  }

  void _saveNow() => _repo.save(_collect());

  void _addCustom() {
    setState(() => _custom.add((TextEditingController(), TextEditingController())));
  }

  void _removeCustom(int i) {
    final (k, v) = _custom.removeAt(i);
    k.dispose();
    v.dispose();
    setState(() {});
    _changed();
  }

  Future<void> _pickBirthDate() async {
    final ctrl = _fields[ProfileField.birthDate]!;
    DateTime? initial;
    try {
      initial = DateFormat('dd/MM/yyyy').parseStrict(ctrl.text);
    } catch (_) {}
    final d = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(1985),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d == null) return;
    ctrl.text = DateFormat('dd/MM/yyyy').format(d);
    _changed();
  }

  Widget _field(ProfileField f, {TextInputType? keyboard, bool upper = false, Widget? suffix, String? hint, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _fields[f],
        keyboardType: keyboard,
        maxLength: maxLength,
        textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.words,
        inputFormatters: upper ? [_UpperCaseFormatter()] : null,
        decoration: InputDecoration(labelText: f.label, hintText: hint, suffixIcon: suffix, counterText: ''),
        onChanged: (_) => _changed(),
      ),
    );
  }

  Widget _row(List<Widget> children) => LayoutBuilder(
        builder: (context, c) => c.maxWidth < 420
            ? Column(children: children)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: children[i]),
                  ],
                ],
              ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cf = _fields[ProfileField.taxCode]!.text.trim();
    final cfWarning = cf.isNotEmpty && !RegExp(r'^[A-Z0-9]{16}$').hasMatch(cf.toUpperCase());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        actions: [
          if (_savedHint)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(children: [
                Icon(Icons.check, size: 18, color: c.success),
                const SizedBox(width: 4),
                Text('Salvato', style: TextStyle(color: c.success)),
              ]),
            ),
        ],
      ),
      body: PageFrame(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            Text(
              'Questi dati servono per compilare i moduli in un tocco. Restano solo su questo dispositivo.',
              style: TextStyle(color: c.secondary),
            ),
            _section('Persona'),
            _row([_field(ProfileField.firstName), _field(ProfileField.lastName)]),
            _row([
              _field(
                ProfileField.birthDate,
                keyboard: TextInputType.datetime,
                hint: 'gg/mm/aaaa',
                suffix: IconButton(tooltip: 'Scegli la data', icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickBirthDate),
              ),
              _field(ProfileField.birthPlace),
            ]),
            _field(ProfileField.taxCode, upper: true, maxLength: 16),
            if (cfWarning)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text('Il codice fiscale di solito ha 16 caratteri.', style: TextStyle(color: c.secondary, fontSize: 13)),
              ),
            _section('Residenza'),
            _field(ProfileField.address, hint: 'Via Roma 1'),
            _row([
              _field(ProfileField.zip, keyboard: TextInputType.number, maxLength: 5),
              _field(ProfileField.city),
              _field(ProfileField.province, upper: true, maxLength: 2, hint: 'RM'),
            ]),
            _section('Contatti'),
            _row([
              _field(ProfileField.phone, keyboard: TextInputType.phone),
              _field(ProfileField.email, keyboard: TextInputType.emailAddress),
            ]),
            _section('Altri dati'),
            for (var i = 0; i < _custom.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _custom[i].$1,
                        decoration: const InputDecoration(labelText: 'Nome del dato', hintText: 'Patente'),
                        onChanged: (_) => _changed(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _custom[i].$2,
                        decoration: const InputDecoration(labelText: 'Valore'),
                        onChanged: (_) => _changed(),
                      ),
                    ),
                    IconButton(tooltip: 'Rimuovi', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeCustom(i)),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _addCustom, icon: const Icon(Icons.add), label: const Text('Aggiungi un dato')),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
