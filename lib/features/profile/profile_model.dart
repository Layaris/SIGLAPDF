import 'package:flutter/foundation.dart';

/// Campo personalizzato chiave/valore.
@immutable
class CustomField {
  const CustomField(this.key, this.value);
  final String key;
  final String value;

  Map<String, dynamic> toMap() => {'key': key, 'value': value};
  factory CustomField.fromMap(Map<String, dynamic> m) =>
      CustomField((m['key'] as String? ?? '').trim(), (m['value'] as String? ?? '').trim());

  @override
  bool operator ==(Object other) => other is CustomField && other.key == key && other.value == value;
  @override
  int get hashCode => Object.hash(key, value);
}

/// Campi fissi del profilo, con etichetta italiana.
enum ProfileField {
  firstName('Nome'),
  lastName('Cognome'),
  birthDate('Data di nascita'),
  birthPlace('Luogo di nascita'),
  taxCode('Codice fiscale'),
  address('Indirizzo'),
  zip('CAP'),
  city('Città'),
  province('Provincia'),
  phone('Telefono'),
  email('Email'),
  gender('Sesso');

  const ProfileField(this.label);
  final String label;
}

/// Profilo dati per l'autocompilazione.
@immutable
class Profile {
  const Profile({this.values = const {}, this.custom = const []});

  final Map<ProfileField, String> values;
  final List<CustomField> custom;

  String operator [](ProfileField f) => values[f]?.trim() ?? '';

  String get fullName => [this[ProfileField.firstName], this[ProfileField.lastName]].where((s) => s.isNotEmpty).join(' ');

  /// Iniziali "M.R." da nome e cognome.
  String get initials {
    final parts = fullName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    return parts.map((s) => '${s[0].toUpperCase()}.').join();
  }

  bool get isEmpty => values.values.every((v) => v.trim().isEmpty) && custom.isEmpty;

  Profile copyWithField(ProfileField f, String value) => Profile(values: {...values, f: value.trim()}, custom: custom);

  Profile copyWith({Map<ProfileField, String>? values, List<CustomField>? custom}) =>
      Profile(values: values ?? this.values, custom: custom ?? this.custom);

  /// Voci da mostrare per l'inserimento rapido: solo quelle compilate.
  List<(String label, String value)> get filledEntries => [
        if (fullName.isNotEmpty) ('Nome e cognome', fullName),
        for (final f in ProfileField.values)
          if (this[f].isNotEmpty && f != ProfileField.gender) (f.label, this[f]),
        if (this[ProfileField.address].isNotEmpty && this[ProfileField.city].isNotEmpty) ('Indirizzo completo', fullAddress),
        for (final c in custom)
          if (c.key.isNotEmpty && c.value.isNotEmpty) (c.key, c.value),
      ];

  /// "Via Roma 1, 00100 Roma (RM)".
  String get fullAddress {
    final cityPart = [
      this[ProfileField.zip],
      this[ProfileField.city],
      if (this[ProfileField.province].isNotEmpty) '(${this[ProfileField.province]})',
    ].where((s) => s.isNotEmpty).join(' ');
    return [this[ProfileField.address], cityPart].where((s) => s.isNotEmpty).join(', ');
  }

  Map<String, dynamic> toMap() => {
        for (final f in ProfileField.values) f.name: this[f],
        'custom': [for (final c in custom) c.toMap()],
      };

  factory Profile.fromMap(Map<String, dynamic> m) {
    final values = <ProfileField, String>{};
    for (final f in ProfileField.values) {
      final v = m[f.name];
      if (v is String && v.trim().isNotEmpty) values[f] = v.trim();
    }
    final rawCustom = m['custom'];
    final custom = rawCustom is List
        ? rawCustom.whereType<Map<String, dynamic>>().map(CustomField.fromMap).where((c) => c.key.isNotEmpty).toList()
        : <CustomField>[];
    return Profile(values: values, custom: custom);
  }

  /// Unione: completa solo i campi vuoti e aggiunge i personalizzati mancanti.
  Profile mergedWith(Profile other) {
    final merged = {...values};
    for (final f in ProfileField.values) {
      if (this[f].isEmpty && other[f].isNotEmpty) merged[f] = other[f];
    }
    final keys = custom.map((c) => c.key.toLowerCase()).toSet();
    return Profile(values: merged, custom: [...custom, ...other.custom.where((c) => !keys.contains(c.key.toLowerCase()))]);
  }
}

/// Profilo con un nome (es. "Io", "Mamma") per chi compila moduli anche per altri.
@immutable
class NamedProfile {
  const NamedProfile({required this.id, required this.label, required this.profile});
  final String id;
  final String label;
  final Profile profile;

  NamedProfile copyWith({String? label, Profile? profile}) =>
      NamedProfile(id: id, label: label ?? this.label, profile: profile ?? this.profile);

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'data': profile.toMap()};

  static NamedProfile? fromMap(Map<String, dynamic> m) {
    final id = m['id'];
    final data = m['data'];
    if (id is! String || data is! Map) return null;
    final label = (m['label'] as String?)?.trim();
    return NamedProfile(
      id: id,
      label: label == null || label.isEmpty ? 'Profilo' : label,
      profile: Profile.fromMap(data.cast<String, dynamic>()),
    );
  }
}
