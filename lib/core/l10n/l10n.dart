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
String tr(String it, [List<Object?> args = const []]) {
  var s = L10n.isEnglish ? (stringsEn[it] ?? it) : it;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
