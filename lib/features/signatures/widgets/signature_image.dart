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
        // Linea della firma, come sui moduli di carta.
        foregroundDecoration: const _SignatureLineDecoration(),
        child: Image.memory(
          signature.png,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          semanticLabel: '${signature.kind.label}: ${signature.name}',
        ),
      );
}

class _SignatureLineDecoration extends Decoration {
  const _SignatureLineDecoration();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _LinePainter();
}

class _LinePainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final y = offset.dy + size.height * 0.84;
    final x0 = offset.dx + size.width * 0.08, x1 = offset.dx + size.width * 0.92;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), Paint()
      ..color = const Color(0xFFE3E6EB)
      ..strokeWidth = 1);
  }
}
