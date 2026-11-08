import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/pdf_coords.dart';
import '../models/placed_element.dart';

/// Contenuto grafico di un elemento (senza cornice di selezione).
class ElementContent extends StatelessWidget {
  const ElementContent({super.key, required this.element, this.pageWidth = 600});
  final PlacedElement element;

  /// Larghezza della pagina a schermo: serve per lo spessore dei tratti a mano.
  final double pageWidth;

  @override
  Widget build(BuildContext context) {
    final color = Color(element.color);
    return switch (element.type) {
      ElementType.signature || ElementType.initials => element.image == null
          ? const SizedBox.shrink()
          : Image.memory(element.image!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
      ElementType.signedDate => LayoutBuilder(
          builder: (context, c) => Column(
            children: [
              SizedBox(
                height: c.maxHeight * signedDateSplit,
                width: c.maxWidth,
                child: element.image == null ? null : Image.memory(element.image!, fit: BoxFit.contain, gaplessPlayback: true),
              ),
              SizedBox(
                height: c.maxHeight * (1 - signedDateSplit),
                width: c.maxWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    element.text,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: (c.maxHeight * (1 - signedDateSplit) * textBoxFontRatio).clamp(1, 200),
                      height: 1.0,
                      fontFamily: 'Helvetica',
                      fontFamilyFallback: const ['Arial', 'Roboto', 'sans-serif'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ElementType.ink => CustomPaint(painter: InkElementPainter(element.strokes, color, element.inkWidth * pageWidth)),
      ElementType.highlight => ColoredBox(color: const Color(highlightColor).withValues(alpha: highlightOpacity + 0.07)),
      ElementType.text || ElementType.date => LayoutBuilder(
          builder: (context, c) => Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                element.text,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: color,
                  fontSize: (c.maxHeight * textBoxFontRatio).clamp(1, 400),
                  height: 1.0,
                  fontFamily: 'Helvetica',
                  fontFamilyFallback: const ['Arial', 'Roboto', 'sans-serif'],
                ),
              ),
            ),
          ),
        ),
      ElementType.check || ElementType.cross => CustomPaint(painter: MarkPainter(element.type, color)),
    };
  }
}

/// Tratti a mano: punti normalizzati nel riquadro, spessore in pixel.
class InkElementPainter extends CustomPainter {
  InkElementPainter(this.strokes, this.color, this.width);
  final List<List<Offset>> strokes;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width.clamp(0.5, 40.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx * s.width, stroke.first.dy * s.height);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx * s.width, pt.dy * s.height);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(InkElementPainter old) => old.strokes != strokes || old.color != color || old.width != width;
}

/// Spunta e croce disegnate come nel PDF esportato.
class MarkPainter extends CustomPainter {
  MarkPainter(this.type, this.color);
  final ElementType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r.shortestSide * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (type == ElementType.check) {
      final path = Path()
        ..moveTo(s.width * 0.12, s.height * 0.55)
        ..lineTo(s.width * 0.40, s.height * 0.82)
        ..lineTo(s.width * 0.88, s.height * 0.18);
      canvas.drawPath(path, p);
    } else {
      final i = r.deflate(r.shortestSide * 0.15);
      canvas.drawLine(i.topLeft, i.bottomRight, p);
      canvas.drawLine(i.topRight, i.bottomLeft, p);
    }
  }

  @override
  bool shouldRepaint(MarkPainter old) => old.type != type || old.color != color;
}

/// Elemento interattivo sopra la pagina: tocca per selezionare, trascina per spostare,
/// maniglia in basso a destra per ridimensionare.
class ElementView extends StatelessWidget {
  const ElementView({
    super.key,
    required this.element,
    required this.pageSize,
    required this.selected,
    required this.onSelect,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onDelete,
    this.onEdit,
  });

  final PlacedElement element;

  /// Dimensione della pagina sullo schermo, in pixel logici.
  final Size pageSize;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onChangeStart;
  final ValueChanged<PlacedElement> onChanged;
  final VoidCallback onChangeEnd;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  static const _handle = 44.0;

  void _move(DragUpdateDetails d) {
    final r = element.rect;
    onChanged(element.copyWith(rect: r.translate(d.delta.dx / pageSize.width, d.delta.dy / pageSize.height)));
  }

  void _resize(DragUpdateDetails d) {
    final r = element.rect;
    var w = r.w + d.delta.dx / pageSize.width;
    var h = r.h + d.delta.dy / pageSize.height;
    final minW = 12 / pageSize.width, minH = 8 / pageSize.height;
    w = w.clamp(minW, 1 - r.x);
    if (element.keepsAspect) {
      // Mantiene le proporzioni in pixel.
      final aspect = (r.w * pageSize.width) / (r.h * pageSize.height);
      h = (w * pageSize.width / aspect) / pageSize.height;
      if (r.y + h > 1) {
        h = 1 - r.y;
        w = (h * pageSize.height * aspect) / pageSize.width;
      }
    } else {
      h = h.clamp(minH, 1 - r.y);
    }
    onChanged(element.copyWith(rect: NormRect(r.x, r.y, w, h)));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rect = element.rect.toRect(pageSize);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              label: '${element.type.label}${element.type.isText ? ': ${element.text}' : ''}',
              selected: selected,
              button: true,
              onTap: onSelect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSelect,
                onDoubleTap: onEdit,
                onPanStart: (_) {
                  onSelect();
                  onChangeStart();
                },
                onPanUpdate: _move,
                onPanEnd: (_) => onChangeEnd(),
                onPanCancel: onChangeEnd,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: selected ? Border.all(color: c.accent, width: 1.5) : null,
                    color: selected ? c.accent.withValues(alpha: 0.05) : null,
                  ),
                  child: ElementContent(element: element, pageWidth: pageSize.width),
                ),
              ),
            ),
          ),
          if (selected) ...[
            // Maniglie quasi tutte fuori dal riquadro: anche gli elementi piccoli restano trascinabili.
            Positioned(
              right: -_handle + 6,
              top: -_handle + 6,
              child: _ChromeButton(icon: Icons.close, tooltip: 'Elimina', onTap: onDelete, color: c.danger),
            ),
            Positioned(
              right: -_handle + 6,
              bottom: -_handle + 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onChangeStart(),
                onPanUpdate: _resize,
                onPanEnd: (_) => onChangeEnd(),
                onPanCancel: onChangeEnd,
                child: Semantics(
                  container: true,
                  label: 'Ridimensiona',
                  child: SizedBox(
                    width: _handle,
                    height: _handle,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.tooltip, required this.onTap, required this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
}
