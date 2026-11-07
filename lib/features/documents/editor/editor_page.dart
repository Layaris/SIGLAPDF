import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/field_detection/field_detector.dart';
import '../../../services/field_detection/local_text_detector.dart';
import '../../../services/pdf_service.dart';
import '../../settings/signature_lock.dart';
import '../../signatures/new_signature_sheet.dart';
import '../../signatures/signature_model.dart';
import '../../signatures/widgets/signature_image.dart';
import '../autofill/autofill.dart';
import '../autofill/autofill_preview_page.dart';
import '../autofill/form_fields_sheet.dart';
import '../models/placed_element.dart';
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
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => EditorPage(controller: EditorController(fileName: name, bytes: bytes, info: info)),
  ));
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
  double _zoom = 1;
  double _pageWidth = 600;
  static const _gap = 16.0;

  @override
  void dispose() {
    _renderer.dispose();
    _scroll.dispose();
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

  int get _inkColor => InkColors.fromName(AppScope.of(context).settings.value.inkColor).toARGB32();

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  // ---------- Inserimento elementi ----------

  Future<void> addSignature(SignatureKind kind) async {
    if (!await ensureSignaturesUnlocked(context) || !mounted) return;
    final repo = AppScope.of(context).signatures;
    final list = repo.ofKind(kind);
    Signature? chosen;
    if (list.isEmpty) {
      await showNewSignatureSheet(context, initialKind: kind);
      return;
    } else if (list.length == 1) {
      chosen = list.first;
    } else {
      chosen = await _pickSignature(list, kind);
    }
    if (chosen == null || !mounted) return;
    final page = currentPage;
    final f = _factory(page);
    ctrl.add(
      type: kind == SignatureKind.initials ? ElementType.initials : ElementType.signature,
      page: page,
      rect: f.imageRect(chosen.aspectRatio, widthPts: kind == SignatureKind.initials ? 70 : 160, center: _visibleCenter(page)),
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
                Text(kind == SignatureKind.initials ? 'Scegli la sigla' : 'Scegli la firma', style: Theme.of(context).textTheme.titleLarge),
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
                            SizedBox(height: 90, child: SignatureImage(signature: s, padding: const EdgeInsets.all(12))),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(s.isDefault ? '${s.name} · predefinita' : s.name),
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
    final text = preset ?? await showTextInputDialog(context, title: 'Aggiungi testo');
    if (text == null || !mounted) return;
    final page = currentPage;
    ctrl.add(
      type: ElementType.text,
      page: page,
      rect: _factory(page).textRect(text, center: _visibleCenter(page)),
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
      rect: _factory(page).textRect(text, center: _visibleCenter(page)),
      text: text,
      color: _inkColor,
    );
  }

  void addMark(ElementType type) {
    final page = currentPage;
    ctrl.add(type: type, page: page, rect: _factory(page).squareRect(center: _visibleCenter(page)), color: _inkColor);
  }

  /// Sigla tutte le pagine: replica la sigla selezionata, oppure mette la predefinita
  /// in basso a destra su ogni pagina.
  Future<void> initialAllPages() async {
    final sel = ctrl.selected;
    if (sel != null && sel.type == ElementType.initials) {
      final n = ctrl.replicateOnAllPages(sel);
      _snack(n == 0 ? 'Tutte le pagine hanno già la sigla' : 'Sigla aggiunta su $n pagine');
      return;
    }
    if (!await ensureSignaturesUnlocked(context) || !mounted) return;
    final initials = AppScope.of(context).signatures.defaultOf(SignatureKind.initials);
    if (initials == null) {
      _snack('Crea prima una sigla');
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
    _snack('Sigla aggiunta su ${items.length} ${items.length == 1 ? 'pagina' : 'pagine'}');
  }

  Future<void> _editText(PlacedElement e) async {
    final t = await showTextInputDialog(context, title: 'Modifica testo', initial: e.text, action: 'Salva');
    if (t == null) return;
    ctrl.updateElement(e.copyWith(text: t));
  }

  // ---------- Esportazione ----------

  String get exportName {
    final base = ctrl.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return '${base.isEmpty ? 'documento' : base}_firmato.pdf';
  }

  Future<void> export() async {
    ctrl.select(null);
    final nav = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Preparo il PDF…')]),
        ),
      ),
    ));
    Uint8List? out;
    String? error;
    try {
      out = await const PdfService().export(ctrl.bytes, elements: ctrl.elements, formValues: ctrl.changedFormValues);
    } catch (e) {
      error = 'Esportazione non riuscita. Riprova.';
    }
    nav.pop();
    if (!mounted) return;
    if (out == null) {
      _snack(error ?? 'Esportazione non riuscita.');
      return;
    }
    await _showExported(out);
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
              Row(children: [
                Icon(Icons.check_circle, color: AppColors.of(sheet).success),
                const SizedBox(width: 8),
                Text('PDF pronto', style: Theme.of(sheet).textTheme.titleLarge),
              ]),
              const SizedBox(height: 4),
              Text('Firme e testi sono stati fissati nel documento.', style: TextStyle(color: AppColors.of(sheet).secondary)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  final ok = await files.save(fileName: exportName, bytes: out, mimeType: 'application/pdf');
                  if (ok && mounted) _snack('PDF salvato');
                },
                icon: const Icon(Icons.download),
                label: const Text('Salva'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await Printing.sharePdf(bytes: out, filename: exportName);
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Condividi'),
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
        title: const Text('Uscire senza esportare?'),
        content: const Text('Le modifiche a questo documento andranno perse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Resta')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Esci')),
        ],
      ),
    );
    return ok == true;
  }

  // ---------- UI ----------

  // ---------- Campi e profilo ----------

  bool get _hasForm => ctrl.info.fillableFields.isNotEmpty;

  Future<void> openFields({String? focus}) => showFormFieldsSheet(
        context,
        controller: ctrl,
        focusField: focus,
        onAutofill: autofillAcroForm,
      );

  /// Compila i campi AcroForm vuoti con i dati del profilo (abbinati per nome del campo).
  void autofillAcroForm() {
    final profile = AppScope.of(context).profile.value;
    if (profile.isEmpty) {
      _snack('Compila prima il tuo profilo');
      return;
    }
    final values = acroFormValuesFromProfile(ctrl.info.fields, ctrl.formValues, profile, today: todayText());
    ctrl.setFormValues(values);
    _snack(values.isEmpty ? 'Nessun campo da compilare con il profilo' : 'Compilati ${values.length} campi dal profilo');
  }

  /// Inserisce un dato del profilo come testo sulla pagina.
  Future<void> insertProfileData() async {
    final profile = AppScope.of(context).profile.value;
    final entries = profile.filledEntries;
    if (entries.isEmpty) {
      _snack('Il profilo è vuoto: aggiungi i tuoi dati nella sezione Profilo');
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
                child: Text('Inserisci un dato', style: Theme.of(context).textTheme.titleLarge),
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

  /// Motori di riconoscimento attivi. Il motore AI si aggiunge nella fase 6.
  List<FieldDetector> detectors() => const [LocalTextFieldDetector()];

  /// "Compila automaticamente": trova i campi non segnalati e mostra l'anteprima.
  Future<void> autoDetect() async {
    final services = AppScope.of(context);
    final profile = services.profile.value;
    final nav = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Cerco i campi…')])),
      ),
    ));
    final found = <DetectedField>[];
    String? error;
    final avoid = [
      for (final f in ctrl.info.fields)
        if (f.rect != null && f.page >= 0) (f.page, f.rect!),
    ];
    for (final d in detectors()) {
      try {
        found.addAll(await d.detect(DetectionInput(pdf: ctrl.bytes, pages: ctrl.info.pages, avoid: avoid)));
      } catch (e) {
        error = e.toString();
      }
    }
    nav.pop();
    if (!mounted) return;
    if (found.isEmpty) {
      _snack(error ?? 'Nessun campo riconosciuto. Puoi aggiungere testi a mano o provare il riconoscimento AI.');
      return;
    }
    final signature = services.signatures.defaultOf(SignatureKind.signature);
    final proposals = buildProposals(found, profile, today: todayText(), hasSignature: signature != null);
    final confirmed = await nav.push<List<FillProposal>>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AutofillPreviewPage(
        proposals: proposals,
        hasSignature: signature != null,
        note: profile.isEmpty ? 'Il profilo è vuoto: puoi scrivere i valori qui o compilare il profilo.' : null,
      ),
    ));
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
    _snack(items.length == 1 ? 'Inserito 1 campo' : 'Inseriti ${items.length} campi');
  }

  List<Widget> extraTools(BuildContext context) => [
        if (_hasForm) _ToolButton(icon: Icons.list_alt_outlined, label: 'Campi', onTap: openFields),
        _ToolButton(icon: Icons.auto_fix_high_outlined, label: 'Compila auto', onTap: autoDetect),
        _ToolButton(icon: Icons.badge_outlined, label: 'Dati profilo', onTap: insertProfileData),
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
              label: 'Campo ${f.name}',
              child: GestureDetector(
                onTap: () => openFields(focus: f.name),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.10),
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
                  IconButton(tooltip: 'Annulla', onPressed: ctrl.canUndo ? ctrl.undo : null, icon: const Icon(Icons.undo)),
                  IconButton(tooltip: 'Ripeti', onPressed: ctrl.canRedo ? ctrl.redo : null, icon: const Icon(Icons.redo)),
                  Padding(
                    padding: const EdgeInsets.only(right: 12, left: 4),
                    child: FilledButton(onPressed: export, child: const Text('Esporta PDF')),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(child: _pages()),
                  if (ctrl.selected != null) _selectionBar(ctrl.selected!) else _toolbar(),
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
    return LayoutBuilder(builder: (context, constraints) {
      final base = (constraints.maxWidth - _gap * 2).clamp(200.0, 900.0);
      _pageWidth = base * _zoom;
      final totalWidth = _pageWidth + _gap * 2;
      final list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: _gap / 2),
        itemCount: ctrl.pageCount,
        itemBuilder: (context, i) {
          final info = ctrl.info.pages[i];
          final size = Size(_pageWidth, _pageWidth / info.aspectRatio);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: _gap / 2),
            child: Center(
              child: Semantics(
                label: 'Pagina ${i + 1} di ${ctrl.pageCount}',
                child: SizedBox.fromSize(
                  size: size,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => ctrl.select(null),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: PdfPageImage(renderer: _renderer, page: i, widthPts: info.visual.width)),
                        ..._formOverlays(i, size),
                        for (final e in ctrl.elementsOn(i))
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
            child: ColoredBox(
              color: c.paper,
              child: totalWidth > constraints.maxWidth
                  ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: totalWidth, child: list))
                  : list,
            ),
          ),
          Positioned(right: 12, bottom: 12, child: _zoomControls()),
        ],
      );
    });
  }

  Widget _zoomControls() {
    final c = AppColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Riduci',
            onPressed: _zoom > 1 ? () => setState(() => _zoom = (_zoom - 0.5).clamp(1, 3)) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('${(_zoom * 100).round()}%', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          IconButton(
            tooltip: 'Ingrandisci',
            onPressed: _zoom < 3 ? () => setState(() => _zoom = (_zoom + 0.5).clamp(1, 3)) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _bar(List<Widget> children) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _toolbar() => _bar([
        _ToolButton(icon: Icons.gesture, label: 'Firma', onTap: () => addSignature(SignatureKind.signature)),
        _ToolButton(icon: Icons.short_text, label: 'Sigla', onTap: () => addSignature(SignatureKind.initials)),
        _ToolButton(icon: Icons.title, label: 'Testo', onTap: addText),
        _ToolButton(icon: Icons.today_outlined, label: 'Data', onTap: addDate),
        _ToolButton(icon: Icons.check, label: 'Spunta', onTap: () => addMark(ElementType.check)),
        _ToolButton(icon: Icons.close, label: 'Croce', onTap: () => addMark(ElementType.cross)),
        _ToolButton(icon: Icons.library_add_check_outlined, label: 'Sigla tutte', onTap: initialAllPages),
        ...extraTools(context),
      ]);

  Widget _selectionBar(PlacedElement e) => _bar([
        if (e.type.isText) _ToolButton(icon: Icons.edit_outlined, label: 'Modifica', onTap: () => _editText(e)),
        if (!e.type.isImage) ...[
          _ToolButton(
            icon: Icons.circle,
            iconColor: InkColors.blue,
            label: 'Blu',
            onTap: () => ctrl.updateElement(e.copyWith(color: InkColors.blue.toARGB32())),
          ),
          _ToolButton(
            icon: Icons.circle,
            iconColor: InkColors.black,
            label: 'Nero',
            onTap: () => ctrl.updateElement(e.copyWith(color: InkColors.black.toARGB32())),
          ),
        ],
        if (ctrl.pageCount > 1)
          _ToolButton(
            icon: Icons.copy_all_outlined,
            label: 'Su tutte',
            onTap: () {
              final n = ctrl.replicateOnAllPages(e);
              _snack(n == 0 ? 'Già presente su tutte le pagine' : 'Copiato su $n pagine');
            },
          ),
        _ToolButton(icon: Icons.delete_outline, label: 'Elimina', onTap: () => ctrl.remove(e.id)),
        _ToolButton(icon: Icons.done, label: 'Fatto', onTap: () => ctrl.select(null)),
      ]);
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.iconColor});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

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
              Icon(icon, color: iconColor ?? c.ink),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
