import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/app_services.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/field_detection/anthropic_detector.dart';
import '../../../services/field_detection/device_detector.dart';
import '../../../services/field_detection/field_detector.dart';
import '../../../services/pdf_service.dart';
import '../../profile/profile_model.dart';
import '../../settings/signature_lock.dart';
import '../../signatures/new_signature_sheet.dart';
import '../../signatures/signature_model.dart';
import '../../signatures/widgets/signature_image.dart';
import '../autofill/autofill.dart';
import '../autofill/autofill_preview_page.dart';
import '../autofill/form_fields_sheet.dart';
import '../models/placed_element.dart';
import '../templates/templates_repository.dart';
import '../widgets/element_view.dart';
import '../widgets/pdf_page_view.dart';
import '../widgets/text_input_dialog.dart';
import 'editor_controller.dart';
import 'element_factory.dart';
import 'page_renderer.dart';

/// Apre l'editor per un PDF. Mostra un errore chiaro se il file non si apre.
Future<void> openPdfEditor(BuildContext context, {required String name, required Uint8List bytes}) async {
  final PdfDocumentInfo info;
  try {
    info = const PdfService().inspect(bytes);
  } on PdfOpenException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EditorPage(
        controller: EditorController(fileName: name, bytes: bytes, info: info),
      ),
    ),
  );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.controller, this.rasterizer});

  final EditorController controller;

  /// Per i test: sostituisce il render con printing.
  final PageRasterizer? rasterizer;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  EditorController get ctrl => widget.controller;
  late final PageRenderer _renderer = PageRenderer(ctrl.bytes, rasterizer: widget.rasterizer);
  final _scroll = ScrollController();

  /// La barra strumenti ricorda dove l'avevi fatta scorrere (anche dopo la barra di selezione).
  final _toolbarScroll = ScrollController();
  double _zoom = 1;

  // Modalità penna.
  bool _drawMode = false;
  int _livePage = -1;
  List<Offset> _liveStroke = const [];
  int? _penColor;
  double _penWidth = 0.004; // frazione della larghezza della pagina

  // Zoom con due dita.
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartZoom = 1;
  double _pageWidth = 600;
  static const _gap = 16.0;

  /// Modello già salvato per questo modulo, proposto in cima alla pagina.
  FormTemplate? _templateOffer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = AppScope.of(context).templates.matching(ctrl.info.fingerprint);
      if (t != null && ctrl.elements.isEmpty) setState(() => _templateOffer = t);
    });
  }

  @override
  void dispose() {
    _renderer.dispose();
    _scroll.dispose();
    _toolbarScroll.dispose();
    ctrl.dispose();
    super.dispose();
  }

  // ---------- Pagine e posizione ----------

  double _pageHeight(int i) => _pageWidth / ctrl.info.pages[i].aspectRatio;

  /// Pagina più visibile al centro dello schermo.
  int get currentPage {
    if (!_scroll.hasClients) return 0;
    final center = _scroll.offset + _scroll.position.viewportDimension / 2;
    var y = _gap;
    for (var i = 0; i < ctrl.pageCount; i++) {
      final h = _pageHeight(i);
      if (center < y + h + _gap / 2) return i;
      y += h + _gap;
    }
    return ctrl.pageCount - 1;
  }

  /// Centro verticale della parte visibile della pagina, normalizzato.
  Offset _visibleCenter(int page) {
    if (!_scroll.hasClients) return const Offset(0.5, 0.5);
    var top = _gap;
    for (var i = 0; i < page; i++) {
      top += _pageHeight(i) + _gap;
    }
    final h = _pageHeight(page);
    final viewTop = _scroll.offset, viewBottom = viewTop + _scroll.position.viewportDimension;
    final visTop = viewTop.clamp(top, top + h), visBottom = viewBottom.clamp(top, top + h);
    final cy = ((visTop + visBottom) / 2 - top) / h;
    return Offset(0.5, cy.isNaN ? 0.5 : cy.clamp(0.1, 0.9));
  }

  ElementFactory _factory(int page) => ElementFactory(ctrl.info.pages[page].visual);

  /// Centro libero per un nuovo elemento: se il punto è occupato scende un po' alla volta.
  Offset _freeCenter(int page, [Offset? start]) {
    var c = start ?? _visibleCenter(page);
    for (var i = 0; i < 12; i++) {
      final busy = ctrl.elementsOn(page).any((e) {
        final r = e.rect;
        return c.dx > r.x - 0.02 && c.dx < r.right + 0.02 && c.dy > r.y - 0.015 && c.dy < r.bottom + 0.015;
      });
      if (!busy) return c;
      c = Offset(c.dx, c.dy + 0.05 > 0.95 ? 0.1 : c.dy + 0.05);
    }
    return c;
  }

  int get _inkColor => InkColors.fromName(AppScope.of(context).settings.value.inkColor).toARGB32();

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  // ---------- Inserimento elementi ----------

  /// Sceglie una firma del tipo richiesto (sblocco, creazione se manca, scelta se più d'una).
  Future<Signature?> _chooseSignature(SignatureKind kind) async {
    if (!await ensureSignaturesUnlocked(context) || !mounted) return null;
    final list = AppScope.of(context).signatures.ofKind(kind);
    if (list.isEmpty) {
      await showNewSignatureSheet(context, initialKind: kind);
      return null;
    }
    if (list.length == 1) return list.first;
    return _pickSignature(list, kind);
  }

  /// Firma con la data di oggi sotto, in un solo elemento.
  Future<void> addSignedDate() async {
    final chosen = await _chooseSignature(SignatureKind.signature);
    if (chosen == null || !mounted) return;
    final page = currentPage;
    ctrl.add(
      type: ElementType.signedDate,
      page: page,
      rect: _factory(page).imageRect(chosen.aspectRatio * signedDateSplit, widthPts: 150, center: _freeCenter(page)),
      image: chosen.png,
      text: todayText(),
      color: _inkColor,
    );
  }

  /// Evidenziatore: riquadro giallo trasparente da posizionare sopra il testo.
  void addHighlight() {
    final page = currentPage;
    final r = _factory(page).textRect(tr('evidenziare questa parte'), fontPts: 11, center: _freeCenter(page));
    ctrl.add(type: ElementType.highlight, page: page, rect: r, color: highlightColor);
  }

  void _toggleDraw() => setState(() {
    _drawMode = !_drawMode;
    _penColor ??= _inkColor;
    _liveStroke = const [];
    if (_drawMode) ctrl.select(null);
  });

  void _strokeEnd() {
    final page = _livePage;
    final pts = _liveStroke;
    setState(() {
      _liveStroke = const [];
      _livePage = -1;
    });
    if (page < 0 || pts.length < 2) return;
    final info = ctrl.info.pages[page];
    final e = inkElementFromStroke(
      pts,
      page: page,
      color: _penColor ?? _inkColor,
      inkWidth: _penWidth,
      pageAspect: info.aspectRatio,
    );
    if (e != null) ctrl.addElement(e, select: false);
  }

  Future<void> addSignature(SignatureKind kind) async {
    final chosen = await _chooseSignature(kind);
    if (chosen == null || !mounted) return;
    final page = currentPage;
    final f = _factory(page);
    ctrl.add(
      type: kind == SignatureKind.initials ? ElementType.initials : ElementType.signature,
      page: page,
      rect: f.imageRect(
        chosen.aspectRatio,
        widthPts: kind == SignatureKind.initials ? 70 : 160,
        center: _freeCenter(page),
      ),
      image: chosen.png,
    );
  }

  Future<Signature?> _pickSignature(List<Signature> list, SignatureKind kind) => showModalBottomSheet<Signature>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              kind == SignatureKind.initials ? tr('Scegli la sigla') : tr('Scegli la firma'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 90,
                          child: SignatureImage(signature: s, padding: const EdgeInsets.all(12)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(s.isDefault ? tr('{0} · predefinita', [s.name]) : s.name),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> addText({String? preset}) async {
    final text = preset ?? await showTextInputDialog(context, title: tr('Aggiungi testo'));
    if (text == null || !mounted) return;
    final page = currentPage;
    ctrl.add(
      type: ElementType.text,
      page: page,
      rect: _factory(page).textRect(text, center: _freeCenter(page)),
      text: text,
      color: _inkColor,
    );
  }

  void addDate() {
    final page = currentPage;
    final text = todayText();
    ctrl.add(
      type: ElementType.date,
      page: page,
      rect: _factory(page).textRect(text, center: _freeCenter(page)),
      text: text,
      color: _inkColor,
    );
  }

  void addMark(ElementType type) {
    final page = currentPage;
    ctrl.add(
      type: type,
      page: page,
      rect: _factory(page).squareRect(center: _freeCenter(page)),
      color: _inkColor,
    );
  }

  /// Sigla tutte le pagine: replica la sigla selezionata, oppure mette la predefinita
  /// in basso a destra su ogni pagina.
  Future<void> initialAllPages() async {
    final sel = ctrl.selected;
    if (sel != null && sel.type == ElementType.initials) {
      final n = ctrl.replicateOnAllPages(sel);
      _snack(n == 0 ? tr('Tutte le pagine hanno già la sigla') : tr('Sigla aggiunta su {0} pagine', [n]));
      return;
    }
    if (!await ensureSignaturesUnlocked(context) || !mounted) return;
    final initials = AppScope.of(context).signatures.defaultOf(SignatureKind.initials);
    if (initials == null) {
      _snack(tr('Crea prima una sigla'));
      await showNewSignatureSheet(context, initialKind: SignatureKind.initials);
      return;
    }
    final items = [
      for (var p = 0; p < ctrl.pageCount; p++)
        PlacedElement(
          id: '',
          type: ElementType.initials,
          page: p,
          rect: _factory(p).initialsCornerRect(initials.aspectRatio),
          image: initials.png,
        ),
    ];
    ctrl.addAll(items);
    _snack(items.length == 1 ? tr('Sigla aggiunta su 1 pagina') : tr('Sigla aggiunta su {0} pagine', [items.length]));
  }

  Future<void> _editText(PlacedElement e) async {
    final t = await showTextInputDialog(context, title: tr('Modifica testo'), initial: e.text, action: tr('Salva'));
    if (t == null) return;
    ctrl.updateElement(e.copyWith(text: t));
  }

  // ---------- Modelli ----------

  Future<void> saveTemplate() async {
    if (ctrl.elements.isEmpty) {
      _snack(tr('Aggiungi prima firma, testi o data: il modello ricorda dove li hai messi'));
      return;
    }
    final base = ctrl.fileName
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'_(firmato|signed)$'), '');
    final name = await showTextInputDialog(
      context,
      title: tr('Salva come modello'),
      initial: base,
      label: tr('Nome del modello'),
      action: tr('Salva'),
    );
    if (name == null || !mounted) return;
    await AppScope.of(context).templates
        .save(name: name, elements: ctrl.elements, pageCount: ctrl.pageCount, fingerprint: ctrl.info.fingerprint);
    _snack(
      ctrl.info.fingerprint == null
          ? tr('Modello salvato. Applicalo dal menu quando riapri questo modulo.')
          : tr('Modello salvato. La prossima volta che apri questo modulo te lo propongo.'),
    );
  }

  Future<void> applyTemplate(FormTemplate t) async {
    setState(() => _templateOffer = null);
    final services = AppScope.of(context);
    final needsSignature = t.elements.any((e) => e.type.isImage);
    if (needsSignature && !await ensureSignaturesUnlocked(context)) return;
    if (!mounted) return;
    final items = elementsFromTemplate(
      t,
      pageCount: ctrl.pageCount,
      today: todayText(),
      signaturePng: services.signatures.defaultOf(SignatureKind.signature)?.png,
      initialsPng: services.signatures.defaultOf(SignatureKind.initials)?.png,
    );
    ctrl.addAll(items);
    final skipped = t.elements.length - items.length;
    _snack(
      skipped > 0
          ? tr('Modello applicato ({0} elementi, {1} saltati: manca la firma o la pagina)', [items.length, skipped])
          : tr('Modello applicato'),
    );
  }

  Future<void> chooseTemplate() async {
    final list = AppScope.of(context).templates.all;
    if (list.isEmpty) {
      _snack(tr('Nessun modello. Posiziona gli elementi e usa "Salva come modello".'));
      return;
    }
    final t = await showModalBottomSheet<FormTemplate>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('Applica un modello'), style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final t in list)
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(t.name),
                subtitle: Text(
                  '${tr('{0} elementi', [t.elements.length])} · ${t.pageCount == 1 ? tr('1 pagina') : tr('{0} pagine', [t.pageCount])}',
                ),
                trailing: t.fingerprint != null && t.fingerprint == ctrl.info.fingerprint
                    ? Text(tr('Questo modulo'))
                    : null,
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (t != null) await applyTemplate(t);
  }

  // ---------- Esportazione ----------

  String get exportName {
    final base = ctrl.fileName
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'_(firmato|signed)$'), ''); // riaperto dai recenti: niente "_firmato_firmato"
    return '${base.isEmpty ? tr('documento') : base}${tr('_firmato')}.pdf';
  }

  Future<void> export() async {
    ctrl.select(null);
    final nav = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [const CircularProgressIndicator(), const SizedBox(width: 20), Text(tr('Preparo il PDF…'))],
            ),
          ),
        ),
      ),
    );
    Uint8List? out;
    String? error;
    try {
      out = await const PdfService().export(ctrl.bytes, elements: ctrl.elements, formValues: ctrl.changedFormValues);
    } catch (e) {
      error = tr('Esportazione non riuscita. Riprova.');
    }
    nav.pop();
    if (!mounted) return;
    if (out == null) {
      _snack(error ?? tr('Esportazione non riuscita.'));
      return;
    }
    final services = AppScope.of(context);
    if (services.settings.value.keepRecents) {
      unawaited(_rememberRecent(services, out));
    }
    await _showExported(out);
  }

  /// Salva il PDF esportato tra i recenti, con una piccola miniatura della prima pagina.
  Future<void> _rememberRecent(AppServices services, Uint8List out) async {
    Uint8List? thumb;
    try {
      final img = await (widget.rasterizer ?? printingRasterizer)(out, 0, 24);
      final data = await img?.toByteData(format: ui.ImageByteFormat.png);
      img?.dispose();
      thumb = data?.buffer.asUint8List();
    } catch (_) {}
    await services.recents.add(name: exportName, pdf: out, pageCount: ctrl.pageCount, thumbnail: thumb);
  }

  Future<void> _showExported(Uint8List out) async {
    final files = AppScope.of(context).files;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.of(sheet).success),
                  const SizedBox(width: 8),
                  Text(tr('PDF pronto'), style: Theme.of(sheet).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr('Firme e testi sono stati fissati nel documento.'),
                style: TextStyle(color: AppColors.of(sheet).secondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  final ok = await files.save(fileName: exportName, bytes: out, mimeType: 'application/pdf');
                  if (ok && mounted) _snack(tr('PDF salvato'));
                },
                icon: const Icon(Icons.download),
                label: Text(tr('Salva')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await Printing.sharePdf(bytes: out, filename: exportName);
                },
                icon: const Icon(Icons.ios_share),
                label: Text(tr('Condividi')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    if (!ctrl.isDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Uscire senza esportare?')),
        content: Text(tr('Le modifiche a questo documento andranno perse.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Resta'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Esci'))),
        ],
      ),
    );
    return ok == true;
  }

  // ---------- UI ----------

  // ---------- Campi e profilo ----------

  bool get _hasForm => ctrl.info.fillableFields.isNotEmpty;

  Future<void> openFields({String? focus}) =>
      showFormFieldsSheet(context, controller: ctrl, focusField: focus, onAutofill: autofillAcroForm);

  /// Chiede quale profilo usare quando ce n'è più di uno. Null se annullato.
  Future<Profile?> _pickProfile() async {
    final repo = AppScope.of(context).profile;
    if (repo.profiles.length == 1) return repo.value;
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('Con quale profilo?'), style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final p in repo.profiles)
              ListTile(
                leading: Icon(p.id == repo.activeId ? Icons.person : Icons.person_outline),
                title: Text(p.label),
                subtitle: p.profile.fullName.isEmpty ? null : Text(p.profile.fullName),
                onTap: () => Navigator.pop(context, p.id),
              ),
          ],
        ),
      ),
    );
    return id == null ? null : repo.byId(id)?.profile;
  }

  /// Compila i campi AcroForm vuoti con i dati del profilo (abbinati per nome del campo).
  Future<void> autofillAcroForm() async {
    final profile = await _pickProfile();
    if (profile == null || !mounted) return;
    if (profile.isEmpty) {
      _snack(tr('Compila prima il tuo profilo'));
      return;
    }
    final values = acroFormValuesFromProfile(ctrl.info.fields, ctrl.formValues, profile, today: todayText());
    ctrl.setFormValues(values);
    _snack(
      values.isEmpty
          ? tr('Nessun campo da compilare con il profilo')
          : tr('Compilati {0} campi dal profilo', [values.length]),
    );
  }

  /// Inserisce un dato del profilo come testo sulla pagina.
  Future<void> insertProfileData() async {
    final profile = await _pickProfile();
    if (profile == null || !mounted) return;
    final entries = profile.filledEntries;
    if (entries.isEmpty) {
      _snack(tr('Il profilo è vuoto: aggiungi i tuoi dati nella sezione Profilo'));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(tr('Inserisci un dato'), style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final (label, value) in entries)
                ListTile(title: Text(value), subtitle: Text(label), onTap: () => Navigator.pop(context, value)),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await addText(preset: picked);
  }

  /// Sceglie il motore: locale (predefinito) oppure AI se attivata nelle impostazioni.
  /// Restituisce null se l'utente annulla.
  Future<List<FieldDetector>?> chooseDetectors() async {
    final services = AppScope.of(context);
    final s = services.settings.value;
    final device = DeviceFieldDetector(ocr: services.ocr);
    if (!s.aiEnabled) return [device];
    final useAi = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Come cercare i campi?'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.offline_bolt_outlined),
                title: Text(tr('Sul dispositivo')),
                subtitle: Text(
                  device.hasOcr
                      ? tr('Offline. Legge anche i documenti scansionati.')
                      : tr('Offline. Funziona con i PDF che contengono testo.'),
                ),
                onTap: () => Navigator.pop(context, false),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(tr('AI avanzata')),
                subtitle: Text(
                  tr('Anche per PDF scansionati. Le pagine vengono inviate come immagini all\'API di Anthropic.'),
                ),
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (useAi == null) return null;
    if (!useAi) return [device];
    if (s.aiApiKey.trim().isEmpty) {
      _snack(tr('Inserisci la chiave API in Impostazioni › Riconoscimento AI'));
      return null;
    }
    return [AnthropicFieldDetector(apiKey: s.aiApiKey, model: s.aiModel)];
  }

  /// "Compila automaticamente": trova i campi non segnalati e mostra l'anteprima.
  Future<void> autoDetect() async {
    final services = AppScope.of(context);
    final profile = services.profile.value;
    final detectors = await chooseDetectors();
    if (detectors == null || !mounted) return;
    final nav = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [const CircularProgressIndicator(), const SizedBox(width: 20), Text(tr('Cerco i campi…'))],
            ),
          ),
        ),
      ),
    );
    final found = <DetectedField>[];
    String? error;
    final avoid = [
      for (final f in ctrl.info.fields)
        if (f.rect != null && f.page >= 0) (f.page, f.rect!),
    ];
    for (final d in detectors) {
      try {
        found.addAll(await d.detect(DetectionInput(pdf: ctrl.bytes, pages: ctrl.info.pages, avoid: avoid)));
      } on AiDetectionException catch (e) {
        error = e.message;
      } on PdfOpenException catch (e) {
        error = e.message;
      } catch (_) {
        error = tr('Riconoscimento non riuscito.');
      }
    }
    nav.pop();
    if (!mounted) return;
    if (found.isEmpty) {
      _snack(
        error ??
            (services.settings.value.aiEnabled || services.ocr != null
                ? tr('Nessun campo riconosciuto. Puoi aggiungere i testi a mano.')
                : tr('Nessun campo riconosciuto. Se è una scansione, usa l\'app Android o il riconoscimento AI.')),
      );
      return;
    }
    final signature = services.signatures.defaultOf(SignatureKind.signature);
    final proposals = buildProposals(found, profile, today: todayText(), hasSignature: signature != null);
    final confirmed = await nav.push<List<FillProposal>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AutofillPreviewPage(
          proposals: proposals,
          hasSignature: signature != null,
          profiles: services.profile.profiles,
          initialProfileId: services.profile.activeId,
          today: todayText(),
          note: profile.isEmpty ? tr('Il profilo è vuoto: puoi scrivere i valori qui o compilare il profilo.') : null,
        ),
      ),
    );
    if (confirmed == null || !mounted) return;
    if (confirmed.any((p) => p.isSignature) && !await ensureSignaturesUnlocked(context)) return;
    final items = proposalsToElements(
      confirmed,
      pages: ctrl.info.pages,
      color: _inkColor,
      signaturePng: signature?.png,
      signatureAspect: signature?.aspectRatio ?? 3,
    );
    ctrl.addAll(items);
    _snack(items.length == 1 ? tr('Inserito 1 campo') : tr('Inseriti {0} campi', [items.length]));
  }

  List<Widget> extraTools(BuildContext context) => [
    if (_hasForm) _ToolButton(icon: Icons.list_alt_outlined, label: tr('Campi'), onTap: openFields),
    _ToolButton(icon: Icons.auto_fix_high_outlined, label: tr('Compila'), onTap: autoDetect),
    _ToolButton(icon: Icons.badge_outlined, label: tr('Dati profilo'), onTap: insertProfileData),
  ];

  /// Evidenzia i campi AcroForm sulla pagina; toccandoli si apre il pannello.
  List<Widget> _formOverlays(int page, Size size) {
    final c = AppColors.of(context);
    return [
      for (final f in ctrl.info.fillableFields)
        if (f.page == page && f.rect != null)
          Positioned.fromRect(
            rect: f.rect!.toRect(size),
            child: Semantics(
              button: true,
              label: tr('Campo {0}', [f.name]),
              child: GestureDetector(
                onTap: () => openFields(focus: f.name),
                child: Container(
                  decoration: BoxDecoration(
                    // Opaco: copre il valore già disegnato nel PDF e mostra solo quello attuale.
                    color: Color.alphaBlend(c.accent.withValues(alpha: 0.10), Colors.white),
                    border: Border.all(color: c.accent.withValues(alpha: 0.45)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.centerLeft,
                  child: _formValuePreview(f),
                ),
              ),
            ),
          ),
    ];
  }

  Widget _formValuePreview(FormFieldInfo f) {
    final v = ctrl.formValues[f.name] ?? '';
    if (f.kind == FormFieldKind.checkbox) {
      return v == 'true' ? const FittedBox(child: Icon(Icons.check, color: Colors.black87)) : const SizedBox.shrink();
    }
    if (v.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(v, maxLines: 1, style: const TextStyle(color: Colors.black87, fontSize: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): ctrl.undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): ctrl.undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): ctrl.redo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): ctrl.redo,
          const SingleActivator(LogicalKeyboardKey.delete): () {
            final s = ctrl.selectedId;
            if (s != null) ctrl.remove(s);
          },
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: ctrl,
            builder: (context, _) => Scaffold(
              appBar: AppBar(
                title: Text(ctrl.fileName, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                    tooltip: tr('Annulla'),
                    onPressed: ctrl.canUndo ? ctrl.undo : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: tr('Ripeti'),
                    onPressed: ctrl.canRedo ? ctrl.redo : null,
                    icon: const Icon(Icons.redo),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr('Altro'),
                    onSelected: (v) => v == 'save' ? saveTemplate() : chooseTemplate(),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'save', child: Text(tr('Salva come modello'))),
                      PopupMenuItem(value: 'apply', child: Text(tr('Applica un modello'))),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton(onPressed: export, child: Text(tr('Esporta PDF'))),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (_templateOffer != null) _templateBanner(_templateOffer!),
                  Expanded(
                    child: Row(
                      children: [
                        if (ctrl.pageCount > 1 && MediaQuery.sizeOf(context).width >= 1000) ...[
                          SizedBox(width: 128, child: _thumbnails(width: 100, onTap: jumpToPage)),
                          VerticalDivider(width: 1, color: AppColors.of(context).line),
                        ],
                        Expanded(child: _pages()),
                      ],
                    ),
                  ),
                  if (_drawMode)
                    _penBar()
                  else if (ctrl.selected != null)
                    _selectionBar(ctrl.selected!)
                  else
                    _toolbar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pages() {
    final c = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = (constraints.maxWidth - _gap * 2).clamp(200.0, 900.0);
        _pageWidth = base * _zoom;
        final totalWidth = _pageWidth + _gap * 2;
        final list = ListView.builder(
          controller: _scroll,
          // In modalità penna un dito disegna invece di scorrere.
          physics: _drawMode ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(vertical: _gap / 2),
          itemCount: ctrl.pageCount,
          itemBuilder: (context, i) {
            final info = ctrl.info.pages[i];
            final size = Size(_pageWidth, _pageWidth / info.aspectRatio);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: _gap / 2),
              child: Center(
                child: Semantics(
                  label: tr('Pagina {0} di {1}', [i + 1, ctrl.pageCount]),
                  child: SizedBox.fromSize(
                    size: size,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => ctrl.select(null),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: PdfPageImage(renderer: _renderer, page: i, widthPts: info.visual.width),
                          ),
                          ..._formOverlays(i, size),
                          for (final e in ctrl.elementsOn(i))
                            if (_drawMode)
                              Positioned.fromRect(
                                rect: e.rect.toRect(size),
                                child: IgnorePointer(
                                  child: ElementContent(element: e, pageWidth: size.width),
                                ),
                              )
                            else
                              ElementView(
                                key: ValueKey(e.id),
                                element: e,
                                pageSize: size,
                                selected: e.id == ctrl.selectedId,
                                onSelect: () => ctrl.select(e.id),
                                onChangeStart: ctrl.beginChange,
                                onChanged: ctrl.updateElement,
                                onChangeEnd: ctrl.endChange,
                                onDelete: () => ctrl.remove(e.id),
                                onEdit: e.type.isText ? () => _editText(e) : null,
                              ),
                          if (_drawMode)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (d) => setState(() {
                                  _livePage = i;
                                  _liveStroke = [
                                    Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height),
                                  ];
                                }),
                                onPanUpdate: (d) {
                                  if (_livePage != i) return;
                                  final p = Offset(
                                    (d.localPosition.dx / size.width).clamp(0.0, 1.0),
                                    (d.localPosition.dy / size.height).clamp(0.0, 1.0),
                                  );
                                  setState(() => _liveStroke = [..._liveStroke, p]);
                                },
                                onPanEnd: (_) => _strokeEnd(),
                                onPanCancel: _strokeEnd,
                                child: CustomPaint(
                                  painter: InkElementPainter(
                                    _livePage == i ? [_liveStroke] : const [],
                                    Color(_penColor ?? _inkColor),
                                    _penWidth * size.width,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
        return Stack(
          children: [
            Positioned.fill(
              // Zoom con due dita (touch) e con Ctrl + rotella (mouse).
              child: Listener(
                onPointerDown: (e) => _pointerDown(e.pointer, e.position),
                onPointerMove: (e) => _pointerMove(e.pointer, e.position),
                onPointerUp: (e) => _pointerUp(e.pointer),
                onPointerCancel: (e) => _pointerUp(e.pointer),
                onPointerSignal: _pointerSignal,
                // Un tocco fuori dalla pagina deseleziona (i tocchi su pagina ed elementi vincono prima).
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => ctrl.select(null),
                  child: ColoredBox(
                    color: c.paper,
                    child: totalWidth > constraints.maxWidth
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(width: totalWidth, child: list),
                          )
                        : list,
                  ),
                ),
              ),
            ),
            Positioned(right: 12, bottom: 12, child: _zoomControls()),
          ],
        );
      },
    );
  }

  void _setZoom(double z) => setState(() => _zoom = z.clamp(1.0, 3.0));

  void _pointerDown(int id, Offset pos) {
    _pointers[id] = pos;
    if (_pointers.length == 2) {
      final ps = _pointers.values.toList();
      _pinchStartDist = (ps[0] - ps[1]).distance;
      _pinchStartZoom = _zoom;
    }
  }

  void _pointerMove(int id, Offset pos) {
    if (!_pointers.containsKey(id)) return;
    _pointers[id] = pos;
    final start = _pinchStartDist;
    if (_pointers.length == 2 && start != null && start > 10) {
      final ps = _pointers.values.toList();
      _setZoom(_pinchStartZoom * (ps[0] - ps[1]).distance / start);
    }
  }

  void _pointerUp(int id) {
    _pointers.remove(id);
    if (_pointers.length < 2) _pinchStartDist = null;
  }

  void _pointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      _setZoom(_zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1));
    }
  }

  /// Scorre fino alla pagina [i].
  void jumpToPage(int i) {
    if (!_scroll.hasClients) return;
    var y = 0.0;
    for (var k = 0; k < i; k++) {
      y += _pageHeight(k) + _gap;
    }
    _scroll.animateTo(
      y.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Miniature delle pagine: tocca per andarci.
  Widget _thumbnails({required double width, required void Function(int) onTap}) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: _scroll,
      builder: (context, _) {
        final current = currentPage;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: ctrl.pageCount,
          itemBuilder: (context, i) {
            final info = ctrl.info.pages[i];
            final selected = i == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                button: true,
                label: tr('Vai alla pagina {0}', [i + 1]),
                child: InkWell(
                  onTap: () => onTap(i),
                  borderRadius: BorderRadius.circular(6),
                  child: Column(
                    children: [
                      Container(
                        width: width,
                        height: width / info.aspectRatio,
                        decoration: BoxDecoration(
                          border: Border.all(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
                        ),
                        child: PdfPageImage(renderer: _renderer, page: i, widthPts: info.visual.width),
                      ),
                      const SizedBox(height: 4),
                      Text('${i + 1}', style: TextStyle(fontSize: 12, color: selected ? c.accent : c.secondary)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPagesSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.6,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
            childAspectRatio: 0.62,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: ctrl.pageCount,
          itemBuilder: (context, i) {
            final info = ctrl.info.pages[i];
            return InkWell(
              onTap: () {
                Navigator.pop(sheet);
                jumpToPage(i);
              },
              child: Column(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: info.aspectRatio,
                      child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(color: AppColors.of(context).line)),
                        child: PdfPageImage(renderer: _renderer, page: i, widthPts: info.visual.width),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _zoomControls() {
    final c = AppColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ctrl.pageCount > 1 && MediaQuery.sizeOf(context).width < 1000)
            IconButton(tooltip: tr('Pagine'), onPressed: _showPagesSheet, icon: const Icon(Icons.grid_view_outlined)),
          IconButton(
            tooltip: tr('Riduci'),
            onPressed: _zoom > 1 ? () => _setZoom(((_zoom - 0.5) * 2).round() / 2) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('${(_zoom * 100).round()}%', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          IconButton(
            tooltip: tr('Ingrandisci'),
            onPressed: _zoom < 3 ? () => _setZoom(((_zoom + 0.5) * 2).round() / 2) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _bar(List<Widget> children, {ScrollController? controller}) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          // La barra scorre anche trascinando con il mouse (web e desktop).
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar() => _bar([
    _ToolButton(icon: Icons.gesture, label: tr('Firma'), onTap: () => addSignature(SignatureKind.signature)),
    _ToolButton(icon: Icons.short_text, label: 'Sigla', onTap: () => addSignature(SignatureKind.initials)),
    _ToolButton(icon: Icons.edit_calendar_outlined, label: tr('Firma e data'), onTap: addSignedDate),
    _ToolButton(icon: Icons.title, label: tr('Testo'), onTap: addText),
    _ToolButton(icon: Icons.today_outlined, label: tr('Data'), onTap: addDate),
    _ToolButton(icon: Icons.check, label: tr('Spunta'), onTap: () => addMark(ElementType.check)),
    _ToolButton(icon: Icons.close, label: tr('Croce'), onTap: () => addMark(ElementType.cross)),
    _ToolButton(icon: Icons.brush_outlined, label: tr('Penna'), onTap: _toggleDraw),
    _ToolButton(icon: Icons.highlight_outlined, label: tr('Evidenzia'), onTap: addHighlight),
    _ToolButton(icon: Icons.library_add_check_outlined, label: tr('Sigla tutte'), onTap: initialAllPages),
    ...extraTools(context),
  ], controller: _toolbarScroll);

  Widget _templateBanner(FormTemplate t) {
    final c = AppColors.of(context);
    return Container(
      color: c.accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize_outlined, color: c.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('Modulo già compilato: vuoi rimettere tutto come in "{0}"?', [t.name]))),
          TextButton(onPressed: () => setState(() => _templateOffer = null), child: Text(tr('No'))),
          FilledButton(onPressed: () => applyTemplate(t), child: Text(tr('Applica'))),
        ],
      ),
    );
  }

  Widget _penBar() {
    final c = AppColors.of(context);
    Widget width(double w, String label) => _ToolButton(
      icon: Icons.horizontal_rule,
      iconSize: 12 + w * 2000,
      iconColor: _penWidth == w ? c.accent : null,
      label: label,
      onTap: () => setState(() => _penWidth = w),
    );
    return _bar([
      _ToolButton(
        icon: Icons.circle,
        iconColor: InkColors.blue,
        label: _penColor == InkColors.blue.toARGB32() ? tr('• Blu') : tr('Blu'),
        onTap: () => setState(() => _penColor = InkColors.blue.toARGB32()),
      ),
      _ToolButton(
        icon: Icons.circle,
        iconColor: InkColors.black,
        label: _penColor == InkColors.black.toARGB32() ? tr('• Nero') : tr('Nero'),
        onTap: () => setState(() => _penColor = InkColors.black.toARGB32()),
      ),
      width(0.0025, tr('Fine')),
      width(0.004, tr('Media')),
      width(0.007, tr('Spessa')),
      _ToolButton(icon: Icons.undo, label: tr('Annulla'), onTap: ctrl.undo),
      _ToolButton(icon: Icons.done, label: tr('Fatto'), onTap: _toggleDraw),
    ]);
  }

  Widget _selectionBar(PlacedElement e) => _bar([
    if (e.type.isText) _ToolButton(icon: Icons.edit_outlined, label: tr('Modifica'), onTap: () => _editText(e)),
    if (e.type.hasInkColor) ...[
      _ToolButton(
        icon: Icons.circle,
        iconColor: InkColors.blue,
        label: tr('Blu'),
        onTap: () => ctrl.updateElement(e.copyWith(color: InkColors.blue.toARGB32())),
      ),
      _ToolButton(
        icon: Icons.circle,
        iconColor: InkColors.black,
        label: tr('Nero'),
        onTap: () => ctrl.updateElement(e.copyWith(color: InkColors.black.toARGB32())),
      ),
    ],
    if (ctrl.pageCount > 1)
      _ToolButton(
        icon: Icons.copy_all_outlined,
        label: tr('Su tutte'),
        onTap: () {
          final n = ctrl.replicateOnAllPages(e);
          _snack(n == 0 ? tr('Già presente su tutte le pagine') : tr('Copiato su {0} pagine', [n]));
        },
      ),
    _ToolButton(icon: Icons.delete_outline, label: tr('Elimina'), onTap: () => ctrl.remove(e.id)),
    _ToolButton(icon: Icons.done, label: tr('Fatto'), onTap: () => ctrl.select(null)),
  ]);
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.iconColor, this.iconSize});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 24,
                child: Icon(icon, color: iconColor ?? c.ink, size: iconSize),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
