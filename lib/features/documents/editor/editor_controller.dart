import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/pdf_coords.dart';
import '../../../services/pdf_service.dart';
import '../models/placed_element.dart';

/// Stato dell'editor di un documento: elementi, valori dei campi, selezione e cronologia.
class EditorController extends ChangeNotifier {
  EditorController({required this.fileName, required this.bytes, required this.info})
      : _formValues = {for (final f in info.fillableFields) f.name: f.value},
        _initialForm = {for (final f in info.fillableFields) f.name: f.value};

  final String fileName;
  final Uint8List bytes;
  final PdfDocumentInfo info;
  static const _uuid = Uuid();

  List<PlacedElement> _elements = const [];
  Map<String, String> _formValues;
  String? _selectedId;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  _Snapshot? _pending;

  /// Valori iniziali dei campi, per sapere cosa è cambiato.
  final Map<String, String> _initialForm;

  List<PlacedElement> get elements => _elements;
  Map<String, String> get formValues => Map.unmodifiable(_formValues);
  String? get selectedId => _selectedId;
  PlacedElement? get selected => _elements.where((e) => e.id == _selectedId).firstOrNull;
  int get pageCount => info.pages.length;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Stato al momento dell'ultima esportazione (null = mai esportato).
  List<PlacedElement>? _exportedElements;
  Map<String, String>? _exportedForm;

  /// Ci sono modifiche non ancora esportate?
  bool get isDirty {
    final els = _exportedElements;
    if (els != null) return !listEquals(els, _elements) || !mapEquals(_exportedForm, _formValues);
    return _elements.isNotEmpty || !mapEquals(_formValues, _initialForm);
  }

  /// Da chiamare dopo un'esportazione riuscita.
  void markExported() {
    _exportedElements = _elements;
    _exportedForm = Map.of(_formValues);
  }

  List<PlacedElement> elementsOn(int page) => _elements.where((e) => e.page == page).toList();

  /// Solo i campi modificati, da passare all'esportazione.
  Map<String, String> get changedFormValues => {
        for (final e in _formValues.entries)
          if (_initialForm[e.key] != e.value) e.key: e.value,
      };

  _Snapshot get _snap => _Snapshot(_elements, Map.of(_formValues));

  /// Campo che si sta digitando: i tasti successivi sullo stesso campo non creano nuovi passi.
  String? _typingField;

  void _record() {
    _typingField = null;
    _undo.add(_snap);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Aggiunge un elemento e lo seleziona.
  PlacedElement add({
    required ElementType type,
    required int page,
    required NormRect rect,
    String text = '',
    Uint8List? image,
    int color = 0xFF1D3FBF,
  }) {
    _record();
    final e = PlacedElement(
      id: _uuid.v4(),
      type: type,
      page: page.clamp(0, pageCount - 1),
      rect: rect.clamped(),
      text: text,
      image: image,
      color: color,
    );
    _elements = [..._elements, e];
    _selectedId = e.id;
    notifyListeners();
    return e;
  }

  /// Aggiunge un elemento già costruito (es. un tratto a mano). Se [select], lo seleziona.
  PlacedElement addElement(PlacedElement e, {bool select = true}) {
    _record();
    final added = e.copyWith(id: _uuid.v4(), page: e.page.clamp(0, pageCount - 1), rect: e.rect.clamped(minSize: 0.003));
    _elements = [..._elements, added];
    if (select) _selectedId = added.id;
    notifyListeners();
    return added;
  }

  /// Aggiunge più elementi in un solo passo di cronologia (es. "Sigla tutte le pagine").
  void addAll(List<PlacedElement> items) {
    if (items.isEmpty) return;
    _record();
    _elements = [
      ..._elements,
      for (final e in items) e.copyWith(id: _uuid.v4(), rect: e.rect.clamped()),
    ];
    _selectedId = null;
    notifyListeners();
  }

  /// Inizio di un trascinamento/ridimensionamento: la cronologia registra solo la fine.
  void beginChange() => _pending ??= _snap;

  /// Aggiorna un elemento durante un gesto (senza cronologia se è in corso un cambio).
  void updateElement(PlacedElement e) {
    final i = _elements.indexWhere((x) => x.id == e.id);
    if (i < 0) return;
    if (_pending == null) _record();
    final next = [..._elements];
    next[i] = e.copyWith(rect: e.rect.clamped());
    _elements = next;
    notifyListeners();
  }

  void endChange() {
    final p = _pending;
    _pending = null;
    if (p == null) return;
    if (!listEquals(p.elements, _elements) || !mapEquals(p.form, _formValues)) {
      _undo.add(p);
      _redo.clear();
      notifyListeners();
    }
  }

  void remove(String id) {
    if (!_elements.any((e) => e.id == id)) return;
    _record();
    _elements = _elements.where((e) => e.id != id).toList();
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }

  /// Duplica un elemento su tutte le altre pagine nella stessa posizione.
  int replicateOnAllPages(PlacedElement source) {
    final items = [
      for (var p = 0; p < pageCount; p++)
        if (p != source.page && !_elements.any((e) => e.page == p && e.type == source.type && e.rect == source.rect))
          source.copyWith(page: p),
    ];
    addAll(items);
    return items.length;
  }

  void setFormValue(String name, String value) {
    if (_formValues[name] == value) return;
    if (_typingField != name) {
      _record();
      _typingField = name;
    }
    _formValues = {..._formValues, name: value};
    notifyListeners();
  }

  /// Imposta più valori in un solo passo di cronologia (autocompilazione).
  void setFormValues(Map<String, String> values) {
    final changed = {for (final e in values.entries) if (_formValues.containsKey(e.key) && _formValues[e.key] != e.value) e.key: e.value};
    if (changed.isEmpty) return;
    _record();
    _formValues = {..._formValues, ...changed};
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snap);
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snap);
    _restore(_redo.removeLast());
  }

  void _restore(_Snapshot s) {
    _typingField = null;
    _elements = s.elements;
    _formValues = Map.of(s.form);
    if (!_elements.any((e) => e.id == _selectedId)) _selectedId = null;
    notifyListeners();
  }
}

class _Snapshot {
  const _Snapshot(this.elements, this.form);
  final List<PlacedElement> elements;
  final Map<String, String> form;
}
