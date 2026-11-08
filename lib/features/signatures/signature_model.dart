import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../core/l10n/l10n.dart';

/// Firma completa o sigla (iniziali).
enum SignatureKind {
  signature('Firma'),
  initials('Sigla');

  const SignatureKind(this._it);
  final String _it;

  /// Etichetta nella lingua dell'interfaccia.
  String get label => tr(_it);

  static SignatureKind parse(Object? v) => v == 'initials' ? initials : signature;
}

/// Come è stata creata la firma.
enum SignatureSource {
  drawn,
  image,
  typed;

  static SignatureSource parse(Object? v) =>
      SignatureSource.values.where((s) => s.name == v).firstOrNull ?? SignatureSource.drawn;
}

/// Firma salvata: sempre un PNG trasparente ritagliato sul contenuto.
@immutable
class Signature {
  const Signature({
    required this.id,
    required this.name,
    required this.kind,
    required this.source,
    required this.png,
    required this.width,
    required this.height,
    required this.createdAt,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final SignatureKind kind;
  final SignatureSource source;
  final Uint8List png;
  final int width;
  final int height;
  final DateTime createdAt;
  final bool isDefault;

  double get aspectRatio => height == 0 ? 3 : width / height;

  Signature copyWith({String? name, bool? isDefault, SignatureKind? kind}) => Signature(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        source: source,
        png: png,
        width: width,
        height: height,
        createdAt: createdAt,
        isDefault: isDefault ?? this.isDefault,
      );

  /// Mappa per l'archivio locale (PNG come byte).
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'source': source.name,
        'png': png,
        'width': width,
        'height': height,
        'createdAt': createdAt.toIso8601String(),
        'isDefault': isDefault,
      };

  /// Mappa per il backup (PNG in base64).
  Map<String, dynamic> toJson() => {...toMap(), 'png': base64Encode(png)};

  factory Signature.fromMap(Map<String, dynamic> m) {
    final raw = m['png'];
    final Uint8List png = switch (raw) {
      final Uint8List b => b,
      final List<dynamic> l => Uint8List.fromList(l.whereType<int>().toList()),
      final String s => base64Decode(s),
      _ => Uint8List(0),
    };
    return Signature(
      id: m['id'] as String,
      name: (m['name'] as String?)?.trim().isNotEmpty == true ? (m['name'] as String).trim() : tr('Firma'),
      kind: SignatureKind.parse(m['kind']),
      source: SignatureSource.parse(m['source']),
      png: png,
      width: (m['width'] as num?)?.toInt() ?? 0,
      height: (m['height'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      isDefault: m['isDefault'] == true,
    );
  }
}
