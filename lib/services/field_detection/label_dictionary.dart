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

  /// Tipo di dato; null = etichetta "bloccante": consuma il testo ma non propone niente
  /// (es. "Nome del padre", "Data di scadenza": non sono dati di chi compila).
  final FieldKind? kind;

  /// Valido solo se sulla stessa riga, prima, c'è un'etichetta di questo tipo (es. "il" dopo "nato a").
  final FieldKind? after;
}

/// Persone diverse da chi compila: "nome del padre", "cognome e nome dell'alunno/a"…
/// (non "del dichiarante/richiedente/sottoscritto", che è chi compila).
const _altri = r"(?:del|della|dell|dei|degli|delle)\s*'?\s*(?!dichiarant|richiedent|sottoscritt|firmatari)[a-z]";

/// Dizionario italiano e inglese delle etichette dei moduli.
/// I testi vanno prima normalizzati con [normalizeForMatching].
/// A parità di posizione vince la corrispondenza più lunga (vedi [findLabels]).
final List<_Pattern> _patterns = [
  // --- Bloccanti: qualificano una parola generica e la rendono "non nostra".
  _Pattern(r'(?:nome|cognome)(?:\s*e\s*(?:nome|cognome))?\s+' + _altri, null),
  _Pattern(r'(?:codice\s*fiscale|data\s*(?:di\s*)?nascita|luogo\s*(?:di\s*)?nascita)\s+' + _altri, null),
  _Pattern(r'\bdata\s*(?:di\s*|del\s*|della\s*)?(?:scadenza|rilascio|inizio|fine|decorrenza|emissione|consegna|presentazione|protocollo|assunzione|matrimonio|morte|decesso)', null),
  _Pattern(r'\bluogo\s*(?:di\s*)?(?:lavoro|rilascio|emissione)', null),
  _Pattern(r"\b(?:al|all'?|spett\.?\s*le|spettabile)\s*comune\b", null),
  _Pattern(r'\bcomune\s*di\s*(?:rilascio|emissione)', null),
  // --- Composti.
  _Pattern(r'luogo\s*(?:e|,|/)\s*data\s*(?:di\s*)?nascita|data\s*(?:e|,|/)\s*luogo\s*(?:di\s*)?nascita|place\s*and\s*date\s*of\s*birth', FieldKind.birthPlaceAndDate),
  _Pattern(r'luogo\s*(?:e|,|/)\s*data|data\s*(?:e|,|/)\s*luogo|place\s*and\s*date', FieldKind.placeAndDate),
  _Pattern(r'data\s*(?:di\s*)?nascita|date\s*of\s*birth|birth\s*date|\bd\.?o\.?b\b', FieldKind.birthDate),
  _Pattern(r'prov(?:incia|\.)?\s*(?:di\s*)?nascita', FieldKind.birthProvince),
  _Pattern(r'(?:luogo|comune|citta)\s*(?:di\s*)?nascita|place\s*of\s*birth|\bborn\s*in\b|\bnat[oa](?:\s*/\s*[ao])?\s+(?:a|in)\b', FieldKind.birthPlace),
  _Pattern(r'\bil\b', FieldKind.birthDate, after: FieldKind.birthPlace),
  _Pattern(r'\bnat[oa](?:\s*/\s*[ao])?\s+il\b|\bborn\s*on\b', FieldKind.birthDate),
  _Pattern(r'cognome\s*e\s*nome|last\s*name\s*and\s*first\s*name|surname\s*and\s*(?:first\s*)?name', FieldKind.lastFirstName),
  _Pattern(r'nome\s*e\s*cognome|full\s*name|\bnominativo\b|(?:il\s*/\s*la\s*)?sottoscritt[oa](?:\s*/\s*a)?', FieldKind.fullName),
  _Pattern(r'\bcognome\b|last\s*name|\bsurname\b|family\s*name', FieldKind.lastName),
  _Pattern(r'\bnome\b|first\s*name|given\s*name|\bname\b', FieldKind.firstName),
  _Pattern(r'codice\s*fiscale|\bcod\s*\.?\s*fisc\b\.?|\bc\s*\.\s*f\b\.?|\bcf\b|tax\s*(?:code|id)|fiscal\s*code', FieldKind.taxCode),
  _Pattern(r'indirizzo\s*(?:di\s*)?(?:residenza|domicilio)|\bindirizzo\b|\b(?:via|viale|piazza|piazzale|corso|largo|vicolo|strada|contrada)\b|\baddress\b|\bstreet\b', FieldKind.address),
  _Pattern(r'residente\s*(?:a|in|nel\s*comune\s*di)\b|\bresidenza\b|domicili(?:o|at[oa](?:\s*/\s*[ao])?)\s*(?:a|in)?\b|\bcomune\b|\bcitta\b|\bcity\b|\btown\b', FieldKind.city),
  _Pattern(r'\bc\.?\s*a\.?\s*p\b\.?|\bzip(?:\s*code)?\b|postal\s*code|\bpostcode\b', FieldKind.zip),
  _Pattern(r'\bprovincia\b|\bprov\b\.?|\bprovince\b|\bstate\b', FieldKind.province),
  _Pattern(r'recapito\s*telefonico|numero\s*di\s*telefono|\btelefono\b|\btel\b\.?|\bcellulare\b|\bcell\b\.?|\bphone\b|\bmobile\b', FieldKind.phone),
  _Pattern(r'\be\s*-?\s*mail\b|posta\s*elettronica|\bpec\b', FieldKind.email),
  _Pattern(r'\bdata\b|\bdate\b', FieldKind.date),
  _Pattern(r'\bluogo\b|\bplace\b', FieldKind.place),
  _Pattern(r'\bfirma\b|\bsignature\b|sign\s*here|\bfirmato\b', FieldKind.signature),
  _Pattern(r'\bsesso\b|\bgender\b|\bsex\b', FieldKind.gender),
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

/// Etichetta di un dato personalizzato del profilo ("Patente", "Cittadinanza"…).
List<String> _customWords(String key) =>
    normalizeForMatching(key.trim()).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1).toList();

/// Identità di un dato personalizzato per confrontare etichetta e chiave ("N. patente" ~ "patente").
String customKeyId(String key) => _customWords(key).join();

_Pattern? _customPattern(String key) {
  final words = _customWords(key);
  if (words.isEmpty) return null;
  return _Pattern('\\b${words.map(RegExp.escape).join(r'[\s./-]*')}\\b', FieldKind.custom);
}

/// Trova le etichette in un testo normalizzato: preferisce le corrispondenze più lunghe
/// e non sovrapposte; restituisce l'elenco ordinato per posizione.
List<LabelMatch> findLabels(String normalized, {List<String> extra = const []}) {
  final all = <(LabelMatch?, int, int, FieldKind?)>[];
  for (final p in [..._patterns, for (final e in extra) ?_customPattern(e)]) {
    for (final m in p.re.allMatches(normalized)) {
      if (m.end > m.start) all.add((p.kind == null ? null : LabelMatch(p.kind!, m.start, m.end), m.start, m.end, p.after));
    }
  }
  all.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
  final chosen = <(LabelMatch?, int, int, FieldKind?)>[];
  for (final c in all) {
    final overlaps = chosen.any((x) => c.$2 < x.$3 && x.$2 < c.$3);
    if (!overlaps) chosen.add(c);
  }
  chosen.sort((a, b) => a.$2.compareTo(b.$2));
  final out = <LabelMatch>[];
  for (final (m, _, _, after) in chosen) {
    if (m == null) continue; // bloccante
    if (after != null && !out.any((x) => x.kind == after)) continue;
    out.add(m);
  }
  // "prov." subito dopo "nato/a a" (prima di qualsiasi etichetta di residenza) è la provincia di nascita.
  for (var i = 0; i < out.length; i++) {
    if (out[i].kind != FieldKind.province) continue;
    final before = out.sublist(0, i);
    final lastBirth = before.lastIndexWhere((x) => x.kind == FieldKind.birthPlace);
    if (lastBirth < 0) continue;
    final residenceBetween = before.sublist(lastBirth + 1).any((x) => x.kind == FieldKind.city || x.kind == FieldKind.address);
    if (!residenceBetween) out[i] = LabelMatch(FieldKind.birthProvince, out[i].start, out[i].end);
  }
  return out;
}

/// Tipo di dato da un nome di campo AcroForm ("codiceFiscale", "data_nascita", "CF"…).
/// Non vince la parola più lunga ("email_address" è un'email, non un indirizzo): conta la priorità.
FieldKind? kindForFieldName(String name) {
  final spaced = name
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-.\[\]0-9]+'), ' ')
      .replaceAllMapped(RegExp(r'\bcodfisc\b|\bcodicefiscale\b', caseSensitive: false), (_) => 'codice fiscale')
      .trim();
  final norm = normalizeForMatching(spaced);
  // Nomi di altre persone o date diverse ("nome_padre", "data_scadenza"): nessun dato del profilo.
  for (final p in _patterns.where((p) => p.kind == null)) {
    if (p.re.hasMatch(norm)) return null;
  }
  if (RegExp(r'\b(?:padre|madre|genitore|figli[oa]|minore|coniuge|alunn[oa]|delegat[oa]|delegante|tutore|bambin[oa]|studente|'
          r'scadenza|rilascio|emissione|decorrenza)\b')
      .hasMatch(norm)) {
    return null;
  }
  final norm2 = norm.replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(r'\bnome\b').hasMatch(norm2) && RegExp(r'\bcognome\b').hasMatch(norm2)) {
    return norm2.indexOf('cognome') < norm2.indexOf(RegExp(r'\bnome\b')) ? FieldKind.lastFirstName : FieldKind.fullName;
  }
  final labels = findLabels(norm);
  if (labels.isEmpty) return null;
  const priority = [
    FieldKind.email, FieldKind.phone, FieldKind.taxCode, FieldKind.birthPlaceAndDate, FieldKind.birthDate,
    FieldKind.birthProvince, FieldKind.birthPlace, FieldKind.zip, FieldKind.province, FieldKind.placeAndDate,
  ];
  for (final k in priority) {
    if (labels.any((l) => l.kind == k)) return k;
  }
  labels.sort((a, b) => b.length.compareTo(a.length));
  return labels.first.kind;
}
