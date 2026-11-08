import 'dart:math' as math;
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/utils/pdf_coords.dart';
import '../pdf_service.dart';
import 'field_detector.dart';
import 'field_kind.dart';
import 'label_dictionary.dart';

/// Parola con il suo riquadro in punti sulla pagina visiva. [glyphs] (facoltativo) ha un riquadro
/// per ogni carattere di [text]; se manca, i caratteri si distribuiscono sulla larghezza.
class WordBox {
  const WordBox(this.text, this.rect, {this.glyphs});
  final String text;
  final Rect rect;
  final List<Rect>? glyphs;
}

/// Trova i campi su una pagina a partire da righe di parole (da testo PDF o da OCR).
List<DetectedField> detectFieldsInLines(List<List<WordBox>> lines, PdfPageInfo info, int page, {String source = 'locale'}) =>
    const LocalTextFieldDetector()._detectOnLines(
      lines.map(_Line.fromWords).whereType<_Line>().toList(),
      info,
      page,
      source: source,
    );

/// Righe di parole in coordinate visive estratte dal testo di una pagina PDF (syncfusion).
List<List<WordBox>> pdfTextLines(PdfTextExtractor extractor, int page, PdfCoords coords) {
  final raw = extractor.extractTextLines(startPageIndex: page, endPageIndex: page);
  return [
    for (final l in raw)
      [
        for (final w in l.wordCollection)
          if (w.text.isNotEmpty)
            WordBox(
              w.text,
              coords.unrotatedRectToVisual(w.bounds),
              glyphs: w.glyphs.length == w.text.length
                  ? [for (final g in w.glyphs) coords.unrotatedRectToVisual(g.bounds)]
                  : null,
            ),
      ],
  ];
}

/// Riconoscimento locale e offline: righe di testo con coordinate (syncfusion) +
/// dizionario delle etichette + ricerca dello spazio vuoto collegato.
class LocalTextFieldDetector implements FieldDetector {
  const LocalTextFieldDetector();

  @override
  String get name => 'locale';

  static final _fill = RegExp(r'_{3,}|\.{4,}|…{2,}');

  @override
  Future<List<DetectedField>> detect(DetectionInput input) async {
    final doc = openPdf(input.pdf);
    try {
      final extractor = PdfTextExtractor(doc);
      final out = <DetectedField>[];
      for (final p in input.targetPages) {
        if (p < 0 || p >= input.pages.length) continue;
        final info = input.pages[p];
        List<List<WordBox>> lines;
        try {
          lines = pdfTextLines(extractor, p, info.coords);
        } catch (_) {
          continue;
        }
        final found = detectFieldsInLines(lines, info, p, source: name);
        for (final f in found) {
          final clash = input.avoid.any((a) => a.$1 == p && _overlap(a.$2, f.rect) > 0.3);
          final dup = out.any((o) => o.page == p && _overlap(o.rect, f.rect) > 0.6);
          if (!clash && !dup) out.add(f);
        }
      }
      return out;
    } finally {
      doc.dispose();
    }
  }

  /// Rapporto tra l'intersezione e l'area più piccola.
  static double _overlap(NormRect a, NormRect b) {
    final ix = math.max(0.0, math.min(a.right, b.right) - math.max(a.x, b.x));
    final iy = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.y, b.y));
    final small = math.min(a.w * a.h, b.w * b.h);
    return small <= 0 ? 0 : ix * iy / small;
  }

  List<DetectedField> _detectOnLines(List<_Line> lines, PdfPageInfo info, int page, {required String source}) {
    if (lines.isEmpty) return const [];
    final size = info.visual;
    lines.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
    final leftMargin = lines.map((l) => l.bounds.left).reduce(math.min).clamp(18.0, size.width * 0.25);
    final rightLimit = size.width - leftMargin;
    final out = <DetectedField>[];

    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      out.addAll(_choices(line, size, page, source));
      final labels = findLabels(line.norm);
      if (labels.isEmpty) continue;
      final h = line.bounds.height;
      for (var i = 0; i < labels.length; i++) {
        final label = labels[i];
        final regionStart = label.end;
        final regionEnd = i + 1 < labels.length ? labels[i + 1].start : line.text.length;
        final region = line.norm.substring(regionStart, regionEnd);
        Rect? box;

        final fill = _fill.firstMatch(region);
        if (fill != null) {
          // Linea "____" o "....": si scrive sopra.
          final a = line.chars[regionStart + fill.start].rect;
          final b = line.chars[regionStart + fill.end - 1].rect;
          box = Rect.fromLTRB(a.left, line.bounds.top - h * 0.15, b.right, line.bounds.bottom - h * 0.1);
        } else if (region.replaceAll(RegExp(r'[\s:;,.\-]'), '').isEmpty) {
          // Solo ":" o spazi dopo l'etichetta: spazio fino alla prossima etichetta o a fine riga.
          var lastIdx = label.end - 1;
          for (var k = regionStart; k < regionEnd; k++) {
            if (line.text[k].trim().isNotEmpty) lastIdx = k;
          }
          final x0 = line.chars[lastIdx].rect.right + h * 0.3;
          final hasNext = i + 1 < labels.length;
          final x1 = hasNext ? line.chars[labels[i + 1].start].rect.left - h * 0.4 : rightLimit;
          if (x1 - x0 >= h * 3) {
            box = Rect.fromLTRB(x0, line.bounds.top - h * 0.1, x1, line.bounds.bottom);
          } else if (!hasNext) {
            box = _below(lines, li, line.chars[label.start].rect.left, size, rightLimit);
          }
        }
        if (label.kind.isChoice) continue; // le scelte si gestiscono con le caselle (sotto)
        if (box == null || box.width < h * 1.5) continue;
        final labelText = line.text.substring(label.start, label.end).replaceAll(RegExp(r'\s+'), ' ').trim();
        out.add(DetectedField(
          page: page,
          kind: label.kind,
          label: labelText,
          rect: NormRect.fromRect(box, size).clamped(minSize: 0.005),
          source: source,
          lineHeight: h / size.height,
        ));
      }
    }
    return out;
  }

  static final _box = RegExp(r'\[\s*\]|\(\s*\)|[☐□◻▢❑❒]');
  static final _word = RegExp(r'[a-zà-ÿ]+');

  /// Etichetta normalizzata di un'opzione (Sì/No, M/F) o null se non è una scelta nota.
  static String? _optionLabel(String w) => switch (w) {
        'si' || 'sì' || 'sí' || 'yes' => 'Sì',
        'no' => 'No',
        'm' || 'maschio' || 'male' => 'M',
        'f' || 'femmina' || 'female' => 'F',
        _ => null,
      };

  /// Caselle di scelta su una riga: "☐ Sì ☐ No", "[ ] M [ ] F", oppure "Sesso: M F" senza caselle.
  List<DetectedField> _choices(_Line line, Size size, int page, String source) {
    final h = line.bounds.height;
    final opts = <ChoiceOption>[];
    final starts = <int>[]; // indice da cui parte ogni opzione (casella o parola), per l'etichetta
    final boxes = _box.allMatches(line.norm).toList();
    // Parola subito dopo / subito prima della casella.
    Match? wordAfter(Match m) {
      final rest = line.norm.substring(m.end);
      final skip = rest.length - rest.trimLeft().length;
      final w = _word.matchAsPrefix(rest, skip);
      return w != null && _optionLabel(w.group(0)!) != null ? w : null;
    }
    Match? wordBefore(Match m) {
      final w = RegExp(r'([a-zà-ÿ]+)\s*$').firstMatch(line.norm.substring(0, m.start));
      return w != null && _optionLabel(w.group(1)!) != null ? w : null;
    }
    // "[ ] Sì [ ] No" (casella prima) oppure "Sì [ ] No [ ]" (casella dopo): vince la lettura con più opzioni.
    final nAfter = boxes.where((m) => wordAfter(m) != null).length;
    final nBefore = boxes.where((m) => wordBefore(m) != null).length;
    final labelFirst = nBefore > nAfter;
    for (final m in boxes) {
      final String label;
      final int start;
      if (labelFirst) {
        final w = wordBefore(m);
        if (w == null) continue;
        label = _optionLabel(w.group(1)!)!;
        start = w.start;
      } else {
        final w = wordAfter(m);
        if (w == null) continue;
        label = _optionLabel(w.group(0)!)!;
        start = m.start;
      }
      final a = line.chars[m.start].rect, b = line.chars[m.end - 1].rect;
      opts.add(ChoiceOption(label, NormRect.fromRect(Rect.fromLTRB(a.left, line.bounds.top, b.right, line.bounds.bottom), size)));
      starts.add(start);
    }
    if (opts.isEmpty) {
      // "Sesso: M F" o "Sesso M/F": lettere sole dopo l'etichetta.
      final g = RegExp(r'\b(?:sesso|gender|sex)\b').firstMatch(line.norm);
      if (g != null) {
        for (final w in RegExp(r'\b([mf])\b').allMatches(line.norm.substring(g.end))) {
          final i = g.end + w.start;
          final r = line.chars[i].rect;
          final side = h * 0.9;
          opts.add(ChoiceOption(_optionLabel(w.group(1)!)!, NormRect.fromRect(Rect.fromCenter(center: r.center, width: side, height: side), size)));
        }
      }
    }
    final labels = opts.map((o) => o.label).toSet();
    final FieldKind kind;
    if (labels.containsAll({'Sì', 'No'})) {
      kind = FieldKind.yesNo;
    } else if (labels.containsAll({'M', 'F'})) {
      kind = FieldKind.gender;
    } else {
      return const [];
    }
    final relevant = opts.where((o) => kind == FieldKind.yesNo ? (o.label == 'Sì' || o.label == 'No') : (o.label == 'M' || o.label == 'F')).toList();
    // Etichetta: il testo prima della prima opzione (es. "Autorizza il trattamento dei dati?").
    final String before;
    final firstOpt = opts.indexOf(relevant.first);
    if (firstOpt >= 0 && firstOpt < starts.length) {
      before = line.text.substring(0, starts[firstOpt]).replaceAll(RegExp(r'\s+'), ' ').trim();
    } else {
      final firstX = relevant.first.rect.x * size.width;
      before = line.chars.where((c) => c.rect.right <= firstX).map((c) => c.ch).join().trim();
    }
    final rect = relevant.map((o) => o.rect.toRect(size)).reduce((a, b) => a.expandToInclude(b));
    return [
      DetectedField(
        page: page,
        kind: kind,
        label: before.isEmpty ? kind.label : (before.length > 50 ? '${before.substring(0, 47)}…' : before),
        rect: NormRect.fromRect(rect, size),
        source: source,
        lineHeight: h / size.height,
        options: relevant,
      ),
    ];
  }

  /// Spazio sotto un'etichetta a fine riga: una riga di soli "____" subito sotto,
  /// oppure uno spazio vuoto alto almeno una riga.
  Rect? _below(List<_Line> lines, int li, double x, Size size, double rightLimit) {
    final line = lines[li];
    final h = line.bounds.height;
    final next = li + 1 < lines.length ? lines[li + 1] : null;
    if (next != null && next.bounds.top - line.bounds.bottom < h * 2.2) {
      final m = _fill.firstMatch(next.norm);
      if (m != null && next.norm.replaceAll(_fill, '').trim().isEmpty) {
        return Rect.fromLTRB(
          next.chars[m.start].rect.left,
          next.bounds.top - h * 0.15,
          next.chars[m.end - 1].rect.right,
          next.bounds.bottom - h * 0.1,
        );
      }
    }
    final top = line.bounds.bottom + h * 0.3;
    final bottom = top + h * 1.3;
    final right = math.min(rightLimit, x + size.width * 0.45);
    final free = !lines.any((l) =>
        l != line && l.bounds.bottom > top && l.bounds.top < bottom && l.bounds.right > x && l.bounds.left < right);
    if (!free || bottom > size.height) return null;
    return Rect.fromLTRB(x, top, right, bottom);
  }
}

class _Char {
  const _Char(this.ch, this.rect);
  final String ch;
  final Rect rect;
}

/// Riga di testo in coordinate visive, con un rettangolo per ogni carattere.
class _Line {
  _Line(this.chars, this.bounds)
      : text = chars.map((c) => c.ch).join(),
        norm = normalizeForMatching(chars.map((c) => c.ch).join());

  final List<_Char> chars;
  final Rect bounds;
  final String text;
  final String norm;

  static _Line? fromWords(List<WordBox> words) {
    final chars = <_Char>[];
    Rect? prev;
    for (final w in words) {
      final t = w.text;
      if (t.isEmpty) continue;
      final wb = w.rect;
      if (prev != null) {
        chars.add(_Char(' ', Rect.fromLTRB(prev.right, wb.top, math.max(prev.right, wb.left), wb.bottom)));
      }
      final glyphs = w.glyphs;
      if (glyphs != null && glyphs.length == t.length) {
        for (var i = 0; i < t.length; i++) {
          chars.add(_Char(t[i], glyphs[i]));
        }
      } else {
        final step = wb.width / t.length;
        for (var i = 0; i < t.length; i++) {
          chars.add(_Char(t[i], Rect.fromLTWH(wb.left + step * i, wb.top, step, wb.height)));
        }
      }
      prev = wb;
    }
    if (chars.isEmpty) return null;
    final bounds = chars.map((c) => c.rect).reduce((a, b) => a.expandToInclude(b));
    if (bounds.height <= 0) return null;
    return _Line(chars, bounds);
  }
}
