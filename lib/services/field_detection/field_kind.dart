import '../../core/l10n/l10n.dart';
import '../../features/profile/profile_model.dart';

/// Tipo di dato atteso in un campo, con il valore proposto dal profilo.
enum FieldKind {
  fullName('Nome e cognome'),
  lastFirstName('Cognome e nome'),
  firstName('Nome'),
  lastName('Cognome'),
  birthDate('Data di nascita'),
  birthPlace('Luogo di nascita'),
  birthProvince('Provincia di nascita'),
  birthPlaceAndDate('Luogo e data di nascita'),
  taxCode('Codice fiscale'),
  address('Indirizzo'),
  zip('CAP'),
  city('Città'),
  province('Provincia'),
  phone('Telefono'),
  email('Email'),
  date('Data'),
  place('Luogo'),
  placeAndDate('Luogo e data'),
  signature('Firma|nome'),
  gender('Sesso'),
  yesNo('Sì / No'),
  custom('Dato personalizzato'),
  text('Testo');

  /// Campi a scelta: si risponde spuntando una casella.
  bool get isChoice => this == gender || this == yesNo;

  const FieldKind(this._it);
  final String _it;

  /// Etichetta nella lingua dell'interfaccia.
  String get label => tr(_it);

  static FieldKind? parse(String? v) {
    if (v == null) return null;
    final s = v.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    for (final k in FieldKind.values) {
      if (k.name.toLowerCase() == s) return k;
    }
    return null;
  }

  /// Valore proposto dal profilo (stringa vuota se manca). Per la firma: vuoto, si usa l'immagine.
  String proposedValue(Profile p, {required String today}) => switch (this) {
        fullName => p.fullName,
        lastFirstName => [p[ProfileField.lastName], p[ProfileField.firstName]].where((s) => s.isNotEmpty).join(' '),
        firstName => p[ProfileField.firstName],
        lastName => p[ProfileField.lastName],
        birthDate => p[ProfileField.birthDate],
        birthPlace => p[ProfileField.birthPlace],
        birthProvince => p[ProfileField.birthProvince].toUpperCase(),
        birthPlaceAndDate => [p[ProfileField.birthPlace], p[ProfileField.birthDate]].where((s) => s.isNotEmpty).join(', '),
        taxCode => p[ProfileField.taxCode].toUpperCase(),
        address => p[ProfileField.address],
        zip => p[ProfileField.zip],
        city => p[ProfileField.city],
        province => p[ProfileField.province].toUpperCase(),
        phone => p[ProfileField.phone],
        email => p[ProfileField.email],
        date => today,
        place => p[ProfileField.city],
        placeAndDate => [p[ProfileField.city], today].where((s) => s.isNotEmpty).join(', '),
        signature => '',
        // Per le scelte il valore è l'etichetta dell'opzione da spuntare.
        gender => p[ProfileField.gender].toUpperCase(),
        yesNo => '',
        custom => '', // dai dati personalizzati del profilo, in base all'etichetta (vedi proposalValue)
        text => '',
      };
}
