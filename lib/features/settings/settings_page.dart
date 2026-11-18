import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_services.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/page_frame.dart';
import '../../services/field_detection/ai_detector.dart';
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
                ButtonSegment(value: ThemeMode.system, label: _segLabel(tr('Sistema'))),
                ButtonSegment(value: ThemeMode.light, label: _segLabel(tr('Chiaro'))),
                ButtonSegment(value: ThemeMode.dark, label: _segLabel(tr('Scuro'))),
              ],
              showSelectedIcon: _roomy(context),
              selected: {s.themeMode},
              onSelectionChanged: (v) => repo.update((x) => x.copyWith(themeMode: v.first)),
            ),
            const SizedBox(height: 16),
            Text(tr('Lingua')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'it', label: _segLabel('Italiano')),
                ButtonSegment(value: 'en', label: _segLabel('English')),
                ButtonSegment(value: 'system', label: _segLabel(tr('Sistema'))),
              ],
              showSelectedIcon: _roomy(context),
              selected: {s.language},
              onSelectionChanged: (v) => repo.update((x) => x.copyWith(language: v.first)),
            ),
            const SizedBox(height: 16),
            Text(tr('Inchiostro predefinito')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'blue', label: _segLabel(tr('Blu')), icon: const Icon(Icons.circle, color: InkColors.blue, size: 14)),
                ButtonSegment(value: 'black', label: _segLabel(tr('Nero')), icon: const Icon(Icons.circle, color: InkColors.black, size: 14)),
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

class _AiSection extends StatelessWidget {
  const _AiSection();

  static String _modeLabel(String mode) => switch (AiProvider.parse(mode)) {
        null => tr('Automatico: prima Gemini, poi NanoGPT, poi Claude'),
        final p => tr('Solo {0}', [p.label]),
      };

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).settings;
    final s = repo.value;
    final c = AppColors.of(context);
    final only = AiProvider.parse(s.aiMode);
    return _Section(title: tr('Riconoscimento AI'), children: [
      SwitchListTile(
        title: Text(tr('Usa il riconoscimento AI')),
        subtitle: Text(tr('Per PDF scansionati o senza testo e per i campi che la ricerca sul dispositivo non trova. Facoltativo.'), style: TextStyle(color: c.secondary)),
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
                  tr('Quando lo usi, le pagine del documento vengono inviate come immagini al servizio scelto (Google Gemini, NanoGPT o Anthropic) con la tua chiave. Non usarlo per documenti che non vuoi condividere. Con il livello gratuito di Gemini, Google può usare i contenuti per migliorare i suoi prodotti. Le chiavi restano solo su questo dispositivo e non vanno nel backup.'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: only?.name ?? 'auto',
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Servizio')),
                items: [
                  for (final m in ['auto', ...AiProvider.values.map((p) => p.name)])
                    DropdownMenuItem(value: m, child: Text(_modeLabel(m), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => repo.update((x) => x.copyWith(aiMode: v ?? 'auto')),
              ),
              if (only == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    tr('Si usa il primo servizio con la chiave; se non risponde (limite o credito finiti, chiave che non va, errore) si passa da soli al successivo.'),
                    style: TextStyle(color: c.secondary, fontSize: 13),
                  ),
                ),
              for (final p in only == null ? AiProvider.values : [only]) _AiProviderFields(key: ValueKey(p), provider: p),
            ],
          ),
        ),
    ]);
  }
}

/// Chiave, modello e prova della connessione di un servizio AI.
class _AiProviderFields extends StatefulWidget {
  const _AiProviderFields({super.key, required this.provider});
  final AiProvider provider;

  @override
  State<_AiProviderFields> createState() => _AiProviderFieldsState();
}

class _AiProviderFieldsState extends State<_AiProviderFields> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _obscure = true;
  bool _init = false;
  bool _testing = false;

  AiProvider get p => widget.provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final a = AppScope.of(context).settings.value.access(p);
    _key = TextEditingController(text: a.apiKey);
    _model = TextEditingController(text: a.model);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  AppSettings _withKey(AppSettings x, String v) => switch (p) {
        AiProvider.gemini => x.copyWith(geminiApiKey: v),
        AiProvider.nanogpt => x.copyWith(nanoGptApiKey: v),
        AiProvider.anthropic => x.copyWith(aiApiKey: v),
      };

  AppSettings _withModel(AppSettings x, String v) => switch (p) {
        AiProvider.gemini => x.copyWith(geminiModel: v),
        AiProvider.nanogpt => x.copyWith(nanoGptModel: v),
        AiProvider.anthropic => x.copyWith(aiModel: v.isEmpty ? AppSettings.defaultAiModel : v),
      };

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    final access = AppScope.of(context).settings.value.access(p);
    setState(() => _testing = true);
    String msg;
    try {
      await testAiConnection(access);
      msg = tr('Connessione a {0} riuscita.', [p.label]);
    } on AiDetectionException catch (e) {
      msg = e.message;
    } catch (_) {
      msg = tr('Connessione a {0} non riuscita. Controlla internet e riprova.', [p.label]);
    }
    if (!mounted) return;
    setState(() => _testing = false);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).settings;
    final c = AppColors.of(context);
    final others = p.models.where((m) => m != p.defaultModel).join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(p.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          SelectableText(tr('Chiave da {0}', [p.keyUrl]), style: TextStyle(color: c.secondary, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: tr('Chiave API {0}', [p.label]),
              suffixIcon: IconButton(
                tooltip: _obscure ? tr('Mostra') : tr('Nascondi'),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (v) => repo.update((x) => _withKey(x, v.trim())),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: tr('Modello {0}', [p.label]),
              helperText: others.isEmpty ? tr('Predefinito: {0}', [p.defaultModel]) : tr('Predefinito: {0}. Altri: {1}', [p.defaultModel, others]),
              helperMaxLines: 3,
            ),
            onChanged: (v) => repo.update((x) => _withModel(x, v.trim())),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _testing || _key.text.trim().isEmpty ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(tr('Prova la connessione')),
            ),
          ),
        ],
      ),
    );
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
        subtitle: Text(
          kIsWeb
              ? tr('Firme, profilo e impostazioni in un file .sigla protetto da password')
              : tr('Firme, profilo e impostazioni in un file .sigla protetto da password. Disinstallando l\'app i dati si cancellano: tieni un backup.'),
          style: TextStyle(color: c.secondary),
        ),
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

/// Etichetta dei pulsanti a segmenti: su una riga sola, rimpicciolita se non c'entra
/// (a 320 px "Sistema" andava a capo a metà parola).
Widget _segLabel(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));

/// Spazio per la spunta accanto all'opzione scelta (sugli schermi stretti si toglie).
bool _roomy(BuildContext context) => MediaQuery.sizeOf(context).width >= 380;
