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
  String? _loadedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).profile;
    for (final f in ProfileField.values) {
      _fields[f] = TextEditingController();
    }
    _load();
    _repo.addListener(_onRepo);
  }

  /// Il profilo attivo può cambiare da fuori (es. import di un backup).
  void _onRepo() {
    if (mounted && _repo.activeId != _loadedId) setState(_load);
  }

  /// Carica nei campi il profilo attivo.
  void _load() {
    final p = _repo.value;
    _loadedId = _repo.activeId;
    for (final f in ProfileField.values) {
      _fields[f]!.text = p[f];
    }
    for (final (k, v) in _custom) {
      k.dispose();
      v.dispose();
    }
    _custom
      ..clear()
      ..addAll([for (final c in p.custom) (TextEditingController(text: c.key), TextEditingController(text: c.value))]);
  }

  Future<void> _switchTo(String id) async {
    _debounce?.cancel();
    await _repo.save(_collect());
    await _repo.setActive(id);
    setState(_load);
  }

  Future<void> _addProfile() async {
    final name = await _askName(title: 'Nuovo profilo', initial: '');
    if (name == null) return;
    _debounce?.cancel();
    await _repo.save(_collect());
    await _repo.addProfile(name);
    setState(_load);
  }

  Future<String?> _askName({required String title, required String initial}) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome', hintText: 'Es. Mamma, Ufficio'),
          onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    // Il controller non si libera qui: il dialogo sta ancora chiudendosi con l'animazione.
    return r;
  }

  Future<void> _profileAction(String a) async {
    final current = _repo.active;
    if (a == 'rename') {
      final n = await _askName(title: 'Rinomina profilo', initial: current.label);
      if (n != null) await _repo.renameProfile(current.id, n);
      setState(() {});
    } else if (a == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Eliminare "${current.label}"?'),
          content: const Text('I dati di questo profilo verranno cancellati.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
          ],
        ),
      );
      if (ok == true && await _repo.removeProfile(current.id)) setState(_load);
    }
  }

  Widget _profileChips() {
    final profiles = _repo.profiles;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in profiles)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p.label),
                selected: p.id == _repo.activeId,
                onSelected: (_) => _switchTo(p.id),
              ),
            ),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Profilo'), onPressed: _addProfile),
        ],
      ),
    );
  }

  Widget _genderField() {
    final g = _fields[ProfileField.gender]!.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text('Sesso', style: TextStyle(color: AppColors.of(context).secondary)),
          const SizedBox(width: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'M', label: Text('M')),
              ButtonSegment(value: 'F', label: Text('F')),
              ButtonSegment(value: '', label: Text('—')),
            ],
            selected: {g == 'M' || g == 'F' ? g : ''},
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              setState(() => _fields[ProfileField.gender]!.text = v.first);
              _changed();
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepo);
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

  /// Intestazione: iniziali, nome e quanti dati sono compilati.
  Widget _header(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final name = [_fields[ProfileField.firstName]!.text.trim(), _fields[ProfileField.lastName]!.text.trim()]
        .where((s) => s.isNotEmpty)
        .join(' ');
    final initials = name.split(' ').where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).take(2).join();
    final filled = _fields.values.where((f) => f.text.trim().isNotEmpty).length;
    final total = _fields.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withValues(alpha: 0.12)),
              child: initials.isEmpty
                  ? Icon(Icons.person_outline, color: c.accent)
                  : Text(initials, style: TextStyle(color: c.accent, fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? _repo.active.label : name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    filled == total ? 'Profilo completo' : '$filled di $total dati compilati',
                    style: TextStyle(color: c.secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: filled / total,
                      minHeight: 6,
                      backgroundColor: c.line,
                      color: filled == total ? c.success : c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cf = _fields[ProfileField.taxCode]!.text.trim();
    final cfWarning = cf.isNotEmpty && !RegExp(r'^[A-Z0-9]{16}$').hasMatch(cf.toUpperCase());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opzioni del profilo',
            onSelected: _profileAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rinomina profilo')),
              if (_repo.profiles.length > 1) const PopupMenuItem(value: 'delete', child: Text('Elimina profilo')),
            ],
          ),
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
            _profileChips(),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge(_fields.values.toList()),
              builder: (context, _) => _header(context),
            ),
            const SizedBox(height: 10),
            Text(
              'Servono per compilare i moduli in un tocco. Restano solo su questo dispositivo.',
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
            _genderField(),
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
