import 'field_kind.dart';

/// Etichetta riconosciuta in un testo.
class LabelMatch {
  const LabelMatch(this.kind, this.start, this.end);
  final FieldKind kind;
  final int start;
  final int end;
  int get length => end - start;
}

class _Pattern {
  _Pattern(String source, this.kind, {this.after}) : re = RegExp(source);
  final RegExp re;
  final FieldKind kind;

  /// Valido solo se sulla stessa riga, prima, c'è un'etichetta di questo tipo (es. "il" dopo "nato a").
  final FieldKind? after;
}

/// Dizionario italiano e inglese delle etichette dei moduli.
/// I testi vanno prima normalizzati con [normalizeForMatching].
final List<_Pattern> _patterns = [
  _Pattern(r'luogo\s*e\s*data|place\s*and\s*date|data\s*e\s*luogo', FieldKind.placeAndDate),
  _Pattern(r'data\s*(?:di\s*)?nascita|date\s*of\s*birth|birth\s*date|\bd\.?o\.?b\b', FieldKind.birthDate),
  _Pattern(r'luogo\s*(?:di\s*)?nascita|place\s*of\s*birth|\bborn\s*in\b|\bnat[oa](?:\s*/\s*a)?\s+(?:a|in)\b', FieldKind.birthPlace),
  _Pattern(r'\bil\b', FieldKind.birthDate, after: FieldKind.birthPlace),
  _Pattern(r'\bnato\s*il\b|\bnata\s*il\b|\bborn\s*on\b', FieldKind.birthDate),
  _Pattern(r'nome\s*e\s*cognome|cognome\s*e\s*nome|full\s*name|\bnominativo\b|(?:il\s*/\s*la\s*)?sottoscritt[oa](?:\s*/\s*a)?', FieldKind.fullName),
  _Pattern(r'\bcognome\b|last\s*name|\bsurname\b|family\s*name', FieldKind.lastName),
  _Pattern(r'\bnome\b|first\s*name|given\s*name|\bname\b', FieldKind.firstName),
  _Pattern(r'codice\s*fiscale|\bc\s*\.\s*f\b\.?|\bcf\b|tax\s*(?:code|id)|fiscal\s*code', FieldKind.taxCode),
  _Pattern(r'residente\s*(?:a|in)\b|\bresidenza\b|\bcomune\b|\bcitta\b|\bcity\b|\btown\b', FieldKind.city),
  _Pattern(r'\bindirizzo\b|\bvia\b|\bpiazza\b|\baddress\b|\bstreet\b', FieldKind.address),
  _Pattern(r'\bc\.?\s*a\.?\s*p\b\.?|\bzip(?:\s*code)?\b|postal\s*code|\bpostcode\b', FieldKind.zip),
  _Pattern(r'\bprovincia\b|\bprov\b\.?|\bprovince\b|\bstate\b', FieldKind.province),
  _Pattern(r'\btelefono\b|\btel\b\.?|\bcellulare\b|\bcell\b\.?|\bphone\b|\bmobile\b', FieldKind.phone),
  _Pattern(r'\be\s*-?\s*mail\b|posta\s*elettronica|\bpec\b', FieldKind.email),
  _Pattern(r'\bdata\b|\bdate\b', FieldKind.date),
  _Pattern(r'\bluogo\b|\bplace\b', FieldKind.place),
  _Pattern(r'\bfirma\b|\bsignature\b|sign\s*here|\bfirmato\b', FieldKind.signature),
];

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n', '’': "'",
};

/// Minuscole e senza accenti, **con la stessa lunghezza** dell'originale
/// (gli indici restano validi per risalire alle coordinate dei caratteri).
String normalizeForMatching(String s) {
  final b = StringBuffer();
  for (final unit in s.split('')) {
    final lower = unit.toLowerCase();
    b.write(_accents[lower] ?? (lower.length == 1 ? lower : ' '));
  }
  return b.toString();
}

/// Trova le etichette in un testo normalizzato: preferisce le corrispondenze più lunghe
/// e non sovrapposte; restituisce l'elenco ordinato per posizione.
List<LabelMatch> findLabels(String normalized) {
  final all = <(LabelMatch, FieldKind?)>[];
  for (final p in _patterns) {
    for (final m in p.re.allMatches(normalized)) {
      if (m.end > m.start) all.add((LabelMatch(p.kind, m.start, m.end), p.after));
    }
  }
  all.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  final chosen = <(LabelMatch, FieldKind?)>[];
  for (final c in all) {
    final overlaps = chosen.any((x) => c.$1.start < x.$1.end && x.$1.start < c.$1.end);
    if (!overlaps) chosen.add(c);
  }
  chosen.sort((a, b) => a.$1.start.compareTo(b.$1.start));
  final out = <LabelMatch>[];
  for (final (m, after) in chosen) {
    if (after != null && !out.any((x) => x.kind == after)) continue;
    out.add(m);
  }
  return out;
}

/// Tipo di dato da un nome di campo AcroForm ("codiceFiscale", "data_nascita", "CF"…).
FieldKind? kindForFieldName(String name) {
  final spaced = name
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-.\[\]0-9]+'), ' ')
      .trim();
  final labels = findLabels(normalizeForMatching(spaced));
  if (labels.isEmpty) return null;
  labels.sort((a, b) => b.length.compareTo(a.length));
  return labels.first.kind;
}
