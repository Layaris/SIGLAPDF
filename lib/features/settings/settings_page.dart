import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_services.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/page_frame.dart';
import '../backup/backup_dialogs.dart';
import '../documents/templates/templates_page.dart';
import 'settings_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Impostazioni'))),
      body: ListenableBuilder(
        listenable: Listenable.merge([services.settings, services.lock]),
        builder: (context, _) => PageFrame(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            // Niente const: le sezioni devono ricostruirsi quando cambiano le impostazioni.
            children: [
              // ignore: prefer_const_constructors
              _AppearanceSection(),
              // ignore: prefer_const_constructors
              _SecuritySection(),
              // ignore: prefer_const_constructors
              _AiSection(),
              // ignore: prefer_const_constructors
              _BackupSection(),
              const _InfoSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ),
            Card(child: Column(children: children)),
          ],
        ),
      );
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).settings;
    final s = repo.value;
    return _Section(title: tr('Aspetto'), children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Tema')),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(tr('Sistema'))),
                ButtonSegment(value: ThemeMode.light, label: Text(tr('Chiaro'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('Scuro'))),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => repo.update((x) => x.copyWith(themeMode: v.first)),
            ),
            const SizedBox(height: 16),
            Text(tr('Lingua')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'it', label: Text('Italiano')),
                const ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'system', label: Text(tr('Sistema'))),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => repo.update((x) => x.copyWith(language: v.first)),
            ),
            const SizedBox(height: 16),
            Text(tr('Inchiostro predefinito')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'blue', label: Text(tr('Blu')), icon: const Icon(Icons.circle, color: InkColors.blue, size: 14)),
                ButtonSegment(value: 'black', label: Text(tr('Nero')), icon: const Icon(Icons.circle, color: InkColors.black, size: 14)),
              ],
              selected: {s.inkColor},
              onSelectionChanged: (v) => repo.update((x) => x.copyWith(inkColor: v.first)),
            ),
            const SizedBox(height: 16),
            Text(tr('Spessore della penna: {0}', [s.penWidth.toStringAsFixed(1)])),
            Slider(
              value: s.penWidth.clamp(1.5, 7.0),
              min: 1.5,
              max: 7,
              divisions: 11,
              semanticFormatterCallback: (v) => tr('Spessore {0}', [v.toStringAsFixed(1)]),
              onChanged: (v) => repo.update((x) => x.copyWith(penWidth: v)),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    final lock = AppScope.of(context).lock;
    final c = AppColors.of(context);
    return _Section(title: tr('Sicurezza'), children: [
      SwitchListTile(
        title: Text(tr('Blocca le firme')),
        subtitle: Text(
          lock.isWeb
              ? tr('Non disponibile nel browser.')
              : tr('Serve impronta, volto o PIN per vedere e usare le firme.'),
          style: TextStyle(color: c.secondary),
        ),
        value: lock.enabled,
        onChanged: lock.isWeb
            ? null
            : (v) async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await lock.setEnabled(v);
                if (!ok) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(v ? tr('Blocco non attivato: autenticazione non disponibile o annullata.') : tr('Blocco non disattivato.')),
                  ));
                }
              },
      ),
    ]);
  }
}

class _AiSection extends StatefulWidget {
  const _AiSection();

  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _obscure = true;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = AppScope.of(context).settings.value;
    _key = TextEditingController(text: s.aiApiKey);
    _model = TextEditingController(text: s.aiModel);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).settings;
    final s = repo.value;
    final c = AppColors.of(context);
    return _Section(title: tr('Riconoscimento AI'), children: [
      SwitchListTile(
        title: Text(tr('Usa il riconoscimento AI')),
        subtitle: Text(tr('Per PDF scansionati o senza testo. Facoltativo.'), style: TextStyle(color: c.secondary)),
        value: s.aiEnabled,
        onChanged: (v) => repo.update((x) => x.copyWith(aiEnabled: v)),
      ),
      if (s.aiEnabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
                child: Text(
                  tr('Quando lo usi, le pagine del documento vengono inviate come immagini all\'API di Anthropic con la tua chiave. Non usarlo per documenti che non vuoi condividere. La chiave resta solo su questo dispositivo e non va nel backup.'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: tr('Chiave API Anthropic'),
                  hintText: 'sk-ant-…',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? tr('Mostra') : tr('Nascondi'),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (v) => repo.update((x) => x.copyWith(aiApiKey: v.trim())),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('Modello'), helperText: tr('Predefinito: {0}', [AppSettings.defaultAiModel])),
                onChanged: (v) => repo.update((x) => x.copyWith(aiModel: v.trim().isEmpty ? AppSettings.defaultAiModel : v.trim())),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final services = AppScope.of(context);
    return _Section(title: tr('Documenti e backup'), children: [
      SwitchListTile(
        title: Text(tr('Ricorda i PDF esportati')),
        subtitle: Text(tr('Elenco "Recenti" in Documenti, solo su questo dispositivo. Non va nel backup.'), style: TextStyle(color: c.secondary)),
        value: services.settings.value.keepRecents,
        onChanged: (v) async {
          await services.settings.update((x) => x.copyWith(keepRecents: v));
          if (!v) await services.recents.clear();
        },
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: Text(tr('Modelli salvati')),
        subtitle: Text(tr('Dove vanno firma e testi nei moduli che compili spesso'), style: TextStyle(color: c.secondary)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TemplatesPage())),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.upload_file_outlined),
        title: Text(tr('Esporta backup')),
        subtitle: Text(tr('Firme, profilo e impostazioni in un file .sigla protetto da password'), style: TextStyle(color: c.secondary)),
        onTap: () => exportBackupFlow(context),
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.download_outlined),
        title: Text(tr('Importa backup')),
        subtitle: Text(tr('Unisci o sostituisci i dati di questo dispositivo'), style: TextStyle(color: c.secondary)),
        onTap: () => importBackupFlow(context),
      ),
    ]);
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = TextStyle(color: c.secondary, height: 1.4);
    final services = AppScope.of(context);
    return _Section(title: tr('Privacy e informazioni'), children: [
      if (services.updates.supported) ...[
        SwitchListTile(
          title: Text(tr('Avvisami delle nuove versioni')),
          subtitle: Text(tr('Una volta al giorno legge la pagina pubblica delle versioni su GitHub. Nessun dato inviato.'),
              style: TextStyle(color: c.secondary)),
          value: services.settings.value.checkUpdates,
          onChanged: (v) => services.settings.update((x) => x.copyWith(checkUpdates: v)),
        ),
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(tr('Controlla ora')),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final u = await services.updates.check(force: true);
            messenger.showSnackBar(SnackBar(
              content: Text(u != null
                  ? tr('Nuova versione disponibile: vai in Documenti per scaricarla')
                  : services.updates.lastCheckFailed
                      ? tr('Controllo non riuscito. Controlla internet e riprova.')
                      : tr('Hai già l\'ultima versione')),
            ));
          },
        ),
        const Divider(height: 1),
      ],
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Privacy'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              tr('Documenti, firme e profilo restano su questo dispositivo. Niente account, niente cloud, nessun tracciamento. Internet serve solo per il riconoscimento AI (se lo attivi) e, sull\'app Android, per l\'avviso di nuova versione (si spegne qui sopra).'),
              style: t,
            ),
            const SizedBox(height: 16),
            Text(tr('Nota legale'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              tr('La firma grafica apposta con Sigla è una firma elettronica semplice ai sensi del Regolamento eIDAS (UE 910/2014). Non è una firma digitale qualificata: per gli atti che la richiedono serve un servizio di firma digitale certificato.'),
              style: t,
            ),
            const SizedBox(height: 16),
            Text('${AppInfo.name} ${AppInfo.version} (build ${AppInfo.build})${kIsWeb ? ' · web' : ''}', style: t),
            const SizedBox(height: 4),
            Text(
              tr('Gratuita per uso personale. PDF con Syncfusion (licenza Community). Font della firma scritta: Great Vibes (SIL Open Font License).'),
              style: t,
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(tr('Licenze')),
        onTap: () => showLicensePage(context: context, applicationName: AppInfo.name, applicationVersion: AppInfo.version),
      ),
    ]);
  }
}
