import 'strings_en.dart';

/// Lingua corrente dell'interfaccia ('it' o 'en'). La imposta l'app all'avvio e quando cambia
/// l'impostazione; il cambio ricostruisce tutto l'albero dei widget.
class L10n {
  static String lang = 'it';

  static bool get isEnglish => lang == 'en';

  /// Lingua effettiva da un'impostazione ('it', 'en', 'system') e dalla lingua del dispositivo.
  static String resolve(String setting, String deviceLanguage) => switch (setting) {
        'en' => 'en',
        'system' => deviceLanguage == 'it' ? 'it' : 'en',
        _ => 'it',
      };
}

/// Traduce un testo dell'interfaccia. La chiave è il testo italiano; `{0}`, `{1}`… sono i
/// segnaposto riempiti con [args]. Senza traduzione resta l'italiano.
///
/// Per le parole con due significati la chiave porta un contesto dopo `|`, che in italiano non si
/// vede: `tr('Annulla|modifica')` → "Annulla" / "Undo", mentre `tr('Annulla')` → "Annulla" / "Cancel".
String tr(String it, [List<Object?> args = const []]) {
  final bar = it.indexOf('|');
  final italian = bar < 0 ? it : it.substring(0, bar);
  final s = L10n.isEnglish ? (stringsEn[it] ?? italian) : italian;
  if (args.isEmpty) return s;
  // Un solo passaggio: un argomento che contiene "{1}" non viene sostituito di nuovo.
  return s.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
    final i = int.parse(m.group(1)!);
    return i < args.length ? '${args[i]}' : m.group(0)!;
  });
}

/// Plurale semplice: [one] se [n] è 1, altrimenti [many] con `{0}` = n.
String trPlural(int n, String one, String many) => n == 1 ? tr(one) : tr(many, [n]);
