import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/l10n/l10n.dart';
import '../core/utils/pdf_coords.dart';
import '../features/documents/models/placed_element.dart';

/// Informazioni su una pagina.
class PdfPageInfo {
  const PdfPageInfo({required this.index, required this.unrotated, required this.rotation});

  final int index;
  final Size unrotated;
  final int rotation;

  PdfCoords get coords => PdfCoords(unrotated, rotation);
  Size get visual => coords.visual;
  double get aspectRatio => visual.height == 0 ? 0.707 : visual.width / visual.height;
}

/// Tipo di campo AcroForm.
enum FormFieldKind { text, checkbox, combo, list, radio, signature, button }

/// Campo AcroForm letto dal PDF.
class FormFieldInfo {
  const FormFieldInfo({
    required this.name,
    required this.kind,
    required this.value,
    required this.page,
    required this.rect,
    this.options = const [],
    this.readOnly = false,
    this.multiline = false,
  });

  final String name;
  final FormFieldKind kind;

  /// Valore attuale: testo, 'true'/'false' per le caselle, valore scelto per liste e radio.
  final String value;

  /// Indice della pagina, -1 se sconosciuto.
  final int page;

  /// Posizione normalizzata sulla pagina visiva (può essere null se sconosciuta).
  final NormRect? rect;
  final List<String> options;
  final bool readOnly;
  final bool multiline;

  bool get isFillable => !readOnly && kind != FormFieldKind.signature && kind != FormFieldKind.button;
}

/// Informazioni sul documento aperto.
class PdfDocumentInfo {
  const PdfDocumentInfo({required this.pages, required this.fields, this.fingerprint});
  final List<PdfPageInfo> pages;
  final List<FormFieldInfo> fields;

  /// Impronta del modulo (numero di pagine + testo delle prime pagine), null se non c'è testo.
  /// Serve a riconoscere un modulo già compilato per riapplicarne il modello.
  final String? fingerprint;

  List<FormFieldInfo> get fillableFields => fields.where((f) => f.isFillable).toList();
}

/// Errore di apertura con messaggio per l'utente.
class PdfOpenException implements Exception {
  const PdfOpenException(this.message);
  final String message;
  @override
  String toString() => message;
}

int _rotationOf(PdfPage p) => switch (p.rotation) {
      PdfPageRotateAngle.rotateAngle90 => 90,
      PdfPageRotateAngle.rotateAngle180 => 180,
      PdfPageRotateAngle.rotateAngle270 => 270,
      _ => 0,
    };

/// Apre un PDF con un messaggio chiaro in caso di errore.
PdfDocument openPdf(Uint8List bytes) {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(1024)).contains('%PDF') == false) {
    throw PdfOpenException(tr('Il file non è un PDF valido.'));
  }
  try {
    return PdfDocument(inputBytes: bytes);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw PdfOpenException(tr('Il PDF è protetto da password. Rimuovi la protezione e riprova.'));
    }
    throw PdfOpenException(tr('Impossibile aprire il PDF: il file potrebbe essere danneggiato.'));
  }
}

/// Logica PDF senza UI: lettura informazioni, campi, esportazione.
class PdfService {
  const PdfService();

  PdfDocumentInfo inspect(Uint8List bytes) {
    final doc = openPdf(bytes);
    try {
      final pages = <PdfPageInfo>[
        for (var i = 0; i < doc.pages.count; i++)
          PdfPageInfo(index: i, unrotated: doc.pages[i].size, rotation: _rotationOf(doc.pages[i])),
      ];
      if (pages.isEmpty) throw PdfOpenException(tr('Il PDF non ha pagine.'));
      return PdfDocumentInfo(pages: pages, fields: _readFields(doc, pages), fingerprint: _fingerprint(doc, pages.length));
    } finally {
      doc.dispose();
    }
  }

  String? _fingerprint(PdfDocument doc, int pageCount) {
    try {
      final text = PdfTextExtractor(doc).extractText(startPageIndex: 0, endPageIndex: pageCount > 1 ? 1 : 0);
      return documentFingerprint(text, pageCount);
    } catch (_) {
      return null;
    }
  }

  List<FormFieldInfo> _readFields(PdfDocument doc, List<PdfPageInfo> pages) {
    final out = <FormFieldInfo>[];
    final PdfFormFieldCollection fields;
    try {
      fields = doc.form.fields;
    } catch (_) {
      return out;
    }
    for (var i = 0; i < fields.count; i++) {
      final f = fields[i];
      final name = f.name;
      if (name == null || name.isEmpty) continue;
      var page = -1;
      NormRect? rect;
      try {
        final p = f.page;
        if (p != null) page = doc.pages.indexOf(p);
        if (page >= 0) {
          final info = pages[page];
          // I bounds dei campi sono nello spazio non ruotato: convertiti solo se la pagina non è ruotata.
          if (info.rotation == 0) {
            rect = NormRect.fromRect(f.bounds, info.unrotated).clamped(minSize: 0.001);
          }
        }
      } catch (_) {}
      final (kind, value, options, multiline) = switch (f) {
        final PdfTextBoxField t => (FormFieldKind.text, t.text, const <String>[], t.multiline),
        final PdfCheckBoxField c => (FormFieldKind.checkbox, c.isChecked ? 'true' : 'false', const <String>[], false),
        final PdfComboBoxField c => (FormFieldKind.combo, _safe(() => c.selectedValue), _items(c.items), false),
        final PdfListBoxField l => (FormFieldKind.list, _safe(() => l.selectedValues.join(', ')), _items(l.items), false),
        final PdfRadioButtonListField r => (
            FormFieldKind.radio,
            _safe(() => r.selectedValue),
            [for (var j = 0; j < r.items.count; j++) r.items[j].value],
            false
          ),
        PdfSignatureField _ => (FormFieldKind.signature, '', const <String>[], false),
        _ => (FormFieldKind.button, '', const <String>[], false),
      };
      out.add(FormFieldInfo(
        name: name,
        kind: kind,
        value: value,
        page: page,
        rect: rect,
        options: options,
        readOnly: f.readOnly,
        multiline: multiline,
      ));
    }
    return out;
  }

  static String _safe(String Function() f) {
    try {
      return f();
    } catch (_) {
      return '';
    }
  }

  static List<String> _items(PdfListFieldItemCollection items) => [for (var j = 0; j < items.count; j++) items[j].value];

  /// Esporta il PDF: compila i campi AcroForm, disegna gli elementi nel contenuto delle pagine,
  /// appiattisce i campi (flatten) e restituisce i byte del nuovo file.
  Future<Uint8List> export(
    Uint8List source, {
    List<PlacedElement> elements = const [],
    Map<String, String> formValues = const {},
    bool flatten = true,
  }) async {
    final doc = openPdf(source);
    try {
      _fillForm(doc, formValues);
      for (final e in elements) {
        if (e.page < 0 || e.page >= doc.pages.count) continue;
        _drawElement(doc.pages[e.page], e);
      }
      if (flatten && doc.form.fields.count > 0) {
        doc.form.setDefaultAppearance(false);
        doc.form.flattenAllFields();
      }
      final bytes = await doc.save();
      return Uint8List.fromList(bytes);
    } finally {
      doc.dispose();
    }
  }

  void _fillForm(PdfDocument doc, Map<String, String> values) {
    if (values.isEmpty) return;
    final fields = doc.form.fields;
    for (var i = 0; i < fields.count; i++) {
      final f = fields[i];
      final v = values[f.name];
      if (v == null || f.readOnly) continue;
      try {
        switch (f) {
          case final PdfTextBoxField t:
            t.text = sanitizeForStandardFont(v);
          case final PdfCheckBoxField c:
            c.isChecked = v == 'true';
          case final PdfComboBoxField c:
            if (v.isNotEmpty) c.selectedValue = v;
          case final PdfListBoxField l:
            if (v.isNotEmpty) l.selectedValues = [v];
          case final PdfRadioButtonListField r:
            if (v.isNotEmpty) r.selectedValue = v;
          default:
            break;
        }
      } catch (_) {
        // Valore non accettato dal campo (es. opzione inesistente): ignorato.
      }
    }
  }

  void _drawElement(PdfPage page, PlacedElement e) {
    final coords = PdfCoords(page.size, _rotationOf(page));
    final g = page.graphics;
    final state = g.save();
    final t = coords.visualTransform;
    if (t.angle != 0) {
      g.translateTransform(t.dx, t.dy);
      g.rotateTransform(t.angle);
    }
    final r = coords.toVisualPoints(e.rect);
    final color = _pdfColor(e.color);
    switch (e.type) {
      case ElementType.signature:
      case ElementType.initials:
        final img = e.image;
        if (img != null && img.isNotEmpty) g.drawImage(PdfBitmap(img), r);
      case ElementType.signedDate:
        final img = e.image;
        final top = Rect.fromLTWH(r.left, r.top, r.width, r.height * signedDateSplit);
        final bottom = Rect.fromLTWH(r.left, top.bottom, r.width, r.height - top.height);
        if (img != null && img.isNotEmpty) {
          // Firma centrata nella parte alta, proporzioni conservate.
          final bmp = PdfBitmap(img);
          final ar = bmp.width / bmp.height;
          var w = top.width, h = w / ar;
          if (h > top.height) {
            h = top.height;
            w = h * ar;
          }
          g.drawImage(bmp, Rect.fromLTWH(top.center.dx - w / 2, top.bottom - h, w, h));
        }
        _drawText(g, e.text, bottom, color, center: true);
      case ElementType.ink:
        final pen = PdfPen(color, width: (e.inkWidth * coords.visual.width).clamp(0.3, 30.0))
          ..lineCap = PdfLineCap.round
          ..lineJoin = PdfLineJoin.round;
        for (final stroke in e.strokes) {
          if (stroke.length < 2) continue;
          final path = PdfPath();
          for (var i = 1; i < stroke.length; i++) {
            path.addLine(
              Offset(r.left + stroke[i - 1].dx * r.width, r.top + stroke[i - 1].dy * r.height),
              Offset(r.left + stroke[i].dx * r.width, r.top + stroke[i].dy * r.height),
            );
          }
          g.drawPath(path, pen: pen);
        }
      case ElementType.highlight:
        g.save();
        g.setTransparency(highlightOpacity, mode: PdfBlendMode.multiply);
        g.drawRectangle(brush: PdfSolidBrush(_pdfColor(highlightColor)), bounds: r);
        g.restore();
      case ElementType.text:
      case ElementType.date:
        _drawText(g, e.text, r, color);
      case ElementType.check:
        final pen = PdfPen(color, width: r.shortestSide * 0.13)
          ..lineCap = PdfLineCap.round
          ..lineJoin = PdfLineJoin.round;
        final path = PdfPath()
          ..addLine(Offset(r.left + r.width * 0.12, r.top + r.height * 0.55), Offset(r.left + r.width * 0.40, r.top + r.height * 0.82))
          ..addLine(Offset(r.left + r.width * 0.40, r.top + r.height * 0.82), Offset(r.left + r.width * 0.88, r.top + r.height * 0.18));
        g.drawPath(path, pen: pen);
      case ElementType.cross:
        final pen = PdfPen(color, width: r.shortestSide * 0.13)..lineCap = PdfLineCap.round;
        final inset = r.deflate(r.shortestSide * 0.15);
        g.drawLine(pen, inset.topLeft, inset.bottomRight);
        g.drawLine(pen, inset.topRight, inset.bottomLeft);
    }
    g.restore(state);
  }

  void _drawText(PdfGraphics g, String raw, Rect r, PdfColor color, {bool center = false}) {
    final text = sanitizeForStandardFont(raw.trim());
    if (text.isEmpty) return;
    var size = r.height * textBoxFontRatio;
    var font = PdfStandardFont(PdfFontFamily.helvetica, size);
    final measured = font.measureString(text);
    if (measured.width > r.width && measured.width > 0) {
      size = size * r.width / measured.width * 0.98;
      font = PdfStandardFont(PdfFontFamily.helvetica, size);
    }
    g.drawString(
      text,
      font,
      brush: PdfSolidBrush(color),
      bounds: Rect.fromLTWH(r.left, r.top, r.width * 1.02, r.height),
      format: PdfStringFormat(
        alignment: center ? PdfTextAlignment.center : PdfTextAlignment.left,
        lineAlignment: PdfVerticalAlignment.middle,
        wordWrap: PdfWordWrapType.none,
      ),
    );
  }

  static PdfColor _pdfColor(int argb) => PdfColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

/// I font standard PDF (Helvetica, WinAnsi) non hanno tutti i caratteri: sostituisce quelli
/// comuni con equivalenti e gli altri con '?'.
String sanitizeForStandardFont(String s) {
  const replacements = {
    '‘': "'", '’': "'", '“': '"', '”': '"', // virgolette curve: presenti in WinAnsi ma
    '–': '-', '—': '-', '…': '...', ' ': ' ', //   normalizzate per sicurezza
    '✓': 'v', '✔': 'v', '✗': 'x', '✘': 'x',
  };
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    if (replacements.containsKey(ch)) {
      b.write(replacements[ch]);
    } else if (rune == 0x20AC || (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)) {
      b.write(ch);
    } else if (rune == 0x0A || rune == 0x09) {
      b.write(' ');
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// Impronta di un modulo: solo lettere e cifre del testo (minuscole, al massimo 4000), più il numero
/// di pagine, ridotte con FNV-1a a 64 bit. Null se il testo è troppo poco (es. scansioni).
String? documentFingerprint(String text, int pageCount) {
  final b = StringBuffer();
  for (final r in text.toLowerCase().runes) {
    if ((r >= 0x30 && r <= 0x39) || (r >= 0x61 && r <= 0x7a) || r >= 0xc0) b.writeCharCode(r);
    if (b.length >= 4000) break;
  }
  final norm = b.toString();
  if (norm.length < 40) return null;
  // Due FNV-1a a 32 bit. La moltiplicazione per il primo FNV (2^24 + 0x193) è scomposta così
  // che nessun valore intermedio superi 2^53: sul web gli interi sono double e darebbero
  // un'impronta diversa da quella calcolata sul telefono.
  int mul(int h) => (h * 0x193 + (h & 0xff) * 0x1000000) % 0x100000000;
  var h1 = 0x811c9dc5, h2 = 0x050c5d1f;
  for (final c in norm.codeUnits) {
    h1 = mul((h1 ^ c) & 0xffffffff);
    h2 = mul((h2 ^ (c + 31)) & 0xffffffff);
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return 'p$pageCount-${hex(h1)}${hex(h2)}';
}
