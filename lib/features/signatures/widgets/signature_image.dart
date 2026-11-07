import 'package:flutter/material.dart';

import '../signature_model.dart';

/// Firma su "carta" bianca: l'inchiostro resta leggibile anche con il tema scuro.
class SignatureImage extends StatelessWidget {
  const SignatureImage({super.key, required this.signature, this.padding = const EdgeInsets.all(16)});

  final Signature signature;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: padding,
        alignment: Alignment.center,
        child: Image.memory(
          signature.png,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          semanticLabel: '${signature.kind.label}: ${signature.name}',
        ),
      );
}
