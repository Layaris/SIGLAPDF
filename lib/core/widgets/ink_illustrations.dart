import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Tratto di firma che si "scrive" da solo (memorabile, ma breve: 1,4 s, una volta sola).
/// Con le animazioni ridotte del sistema compare già completo.
class SignatureFlourish extends StatefulWidget {
  const SignatureFlourish({super.key, this.color, this.strokeWidth = 3.2, this.animate = true});

  final Color? color;
  final double strokeWidth;
  final bool animate;

  @override
  State<SignatureFlourish> createState() => _SignatureFlourishState();
}

class _SignatureFlourishState extends State<SignatureFlourish> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.animate || reduce) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(
          animation: CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic),
          builder: (context, _) => CustomPaint(
            painter: _FlourishPainter(
              progress: Curves.easeInOutCubic.transform(_c.value),
              color: widget.color ?? AppColors.of(context).accent,
              width: widget.strokeWidth,
            ),
          ),
        ),
      );
}

/// Firma stilizzata in un riquadro 300×100, scalata al widget.
Path signaturePath(Size size) {
  final sx = size.width / 300, sy = size.height / 100;
  Offset p(double x, double y) => Offset(x * sx, y * sy);
  final start = p(10, 75);
  final path = Path()..moveTo(start.dx, start.dy);
  void c(double x1, double y1, double x2, double y2, double x, double y) {
    final a = p(x1, y1), b = p(x2, y2), e = p(x, y);
    path.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
  }

  // Asola iniziale, due gobbe, un occhiello e lo svolazzo finale: una firma corsiva stilizzata.
  c(40, 75, 55, 15, 70, 15);
  c(85, 15, 80, 55, 65, 70);
  c(55, 80, 80, 80, 95, 60);
  c(105, 45, 112, 45, 115, 60);
  c(118, 75, 125, 70, 132, 55);
  c(138, 42, 146, 45, 147, 60);
  c(148, 75, 158, 72, 168, 55);
  c(176, 42, 190, 40, 192, 55);
  c(194, 70, 176, 72, 178, 58);
  c(180, 46, 205, 50, 215, 60);
  c(225, 70, 240, 68, 255, 50);
  c(265, 38, 280, 30, 292, 26);
  // Sottolineatura.
  final u = p(60, 90);
  path.moveTo(u.dx, u.dy);
  c(130, 82, 210, 80, 290, 86);
  return path;
}

class _FlourishPainter extends CustomPainter {
  _FlourishPainter({required this.progress, required this.color, required this.width});
  final double progress;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    final metrics = signaturePath(size).computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var remaining = total * progress;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final len = remaining.clamp(0.0, m.length);
      canvas.drawPath(m.extractPath(0, len), paint);
      remaining -= m.length;
    }
  }

  @override
  bool shouldRepaint(_FlourishPainter old) => old.progress != progress || old.color != color;
}

/// Foglio di carta stilizzato con righe di testo, campi compilati, una spunta e una firma.
class SignedSheetIllustration extends StatelessWidget {
  const SignedSheetIllustration({super.key, this.size = const Size(120, 150)});
  final Size size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: size,
        child: CustomPaint(painter: _SheetPainter(c)),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.c);
  final AppColors c;

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.06));
    canvas.drawRRect(r, Paint()..color = Colors.white);
    canvas.drawRRect(r, Paint()
      ..color = const Color(0xFFDADFE7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    // Angolo piegato.
    final fold = s.width * 0.18;
    final corner = Path()
      ..moveTo(s.width - fold, 0)
      ..lineTo(s.width, fold)
      ..lineTo(s.width - fold, fold)
      ..close();
    canvas.drawPath(corner, Paint()..color = const Color(0xFFEFF2F6));
    final grey = Paint()
      ..color = const Color(0xFFCBD2DC)
      ..strokeWidth = s.height * 0.022
      ..strokeCap = StrokeCap.round;
    final ink = Paint()
      ..color = InkColors.blue
      ..strokeWidth = s.height * 0.02
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final m = s.width * 0.14;
    // Titolo e righe.
    canvas.drawLine(Offset(m, s.height * 0.14), Offset(s.width * 0.55, s.height * 0.14), grey..strokeWidth = s.height * 0.03);
    grey.strokeWidth = s.height * 0.018;
    for (final (y, w) in [(0.28, 0.72), (0.38, 0.6), (0.48, 0.68)]) {
      canvas.drawLine(Offset(m, s.height * y), Offset(m + s.width * w * 0.3, s.height * y), grey);
      // Campo compilato in blu dopo l'etichetta.
      canvas.drawLine(Offset(m + s.width * 0.28, s.height * y), Offset(m + s.width * w, s.height * y), ink);
    }
    // Casella con spunta.
    final box = Rect.fromLTWH(m, s.height * 0.58, s.width * 0.1, s.width * 0.1);
    canvas.drawRect(box, Paint()
      ..color = const Color(0xFFCBD2DC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(box.left + box.width * 0.18, box.top + box.height * 0.55)
        ..lineTo(box.left + box.width * 0.42, box.top + box.height * 0.8)
        ..lineTo(box.left + box.width * 0.9, box.top + box.height * 0.15),
      ink,
    );
    canvas.drawLine(Offset(m + s.width * 0.16, box.center.dy), Offset(s.width * 0.7, box.center.dy), grey);
    // Firma sulla linea in basso a destra.
    final sigRect = Rect.fromLTWH(s.width * 0.36, s.height * 0.72, s.width * 0.52, s.height * 0.16);
    canvas.drawLine(Offset(sigRect.left, sigRect.bottom), Offset(sigRect.right, sigRect.bottom), grey..strokeWidth = 1);
    canvas.save();
    canvas.translate(sigRect.left, sigRect.top);
    canvas.drawPath(
      signaturePath(sigRect.size),
      Paint()
        ..color = InkColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.016
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) => false;
}

/// Pallino numerato per i passaggi ("1 Apri · 2 Firma · 3 Esporta").
class StepDot extends StatelessWidget {
  const StepDot(this.n, {super.key});
  final int n;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent.withValues(alpha: 0.12)),
      child: Text('$n', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
