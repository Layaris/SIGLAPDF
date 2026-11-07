import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_colors.dart';
import '../signature_model.dart';
import '../widgets/save_signature_dialog.dart';
import 'ink_model.dart';
import 'ink_renderer.dart';

/// Disegno a mano della firma o della sigla.
class DrawSignaturePage extends StatefulWidget {
  const DrawSignaturePage({super.key, this.kind = SignatureKind.signature});

  final SignatureKind kind;

  @override
  State<DrawSignaturePage> createState() => _DrawSignaturePageState();
}

class _DrawSignaturePageState extends State<DrawSignaturePage> {
  final _drawing = InkDrawing();
  late Color _color;
  late double _width;
  bool _saving = false;
  final Stopwatch _clock = Stopwatch();
  int? _activePointer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context).settings.value;
    _color = InkColors.fromName(s.inkColor);
    _width = s.penWidth;
  }

  @override
  void dispose() {
    _drawing.dispose();
    super.dispose();
  }

  double? _pressureOf(PointerEvent e) {
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    if (!stylus || e.pressureMax - e.pressureMin < 0.01) return null;
    return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
  }

  InkPoint _point(PointerEvent e) =>
      InkPoint(e.localPosition.dx, e.localPosition.dy, pressure: _pressureOf(e), t: _clock.elapsedMilliseconds);

  void _down(PointerDownEvent e) {
    if (_activePointer != null) return; // Un dito alla volta.
    _activePointer = e.pointer;
    _clock
      ..reset()
      ..start();
    _drawing.begin(_point(e), width: _width, color: _color);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    _drawing.extend(_point(e));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _drawing.end();
  }

  Future<void> _save() async {
    if (_drawing.isEmpty || _saving) return;
    final repo = AppScope.of(context).signatures;
    final name = await showSaveSignatureDialog(
      context,
      kind: widget.kind,
      existingCount: repo.ofKind(widget.kind).length,
    );
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    final rendered = await renderStrokesToPng(_drawing.strokes);
    if (rendered == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    await repo.add(
      name: name,
      kind: widget.kind,
      source: SignatureSource.drawn,
      png: rendered.png,
      width: rendered.width,
      height: rendered.height,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isInitials = widget.kind == SignatureKind.initials;
    return Scaffold(
      appBar: AppBar(
        title: Text(isInitials ? 'Disegna la sigla' : 'Disegna la firma'),
        actions: [
          ListenableBuilder(
            listenable: _drawing,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(onPressed: _drawing.isEmpty || _saving ? null : _save, child: const Text('Salva')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                // L'area si adatta allo schermo: alta abbastanza anche sul telefono.
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final ideal = w / (isInitials ? 1.2 : 1.5);
                    // Mai più alta dello spazio disponibile (clamp fallirebbe se maxHeight < 160).
                    final h = ideal < 160 ? (box.maxHeight < 160 ? box.maxHeight : 160.0) : (ideal > box.maxHeight ? box.maxHeight : ideal);
                    return Center(
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: Semantics(
                          label: 'Area di disegno della firma',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: c.line),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Listener(
                                onPointerDown: _down,
                                onPointerMove: _move,
                                onPointerUp: _up,
                                onPointerCancel: _up,
                                behavior: HitTestBehavior.opaque,
                                child: ListenableBuilder(
                                  listenable: _drawing,
                                  builder: (context, _) => CustomPaint(
                                    painter: _InkPainter(_drawing.strokes, showHint: _drawing.isEmpty),
                                    size: Size.infinite,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _Toolbar(
              drawing: _drawing,
              color: _color,
              width: _width,
              onColor: (col) {
                setState(() => _color = col);
                _drawing.recolor(col);
              },
              onWidth: (w) => setState(() => _width = w),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.drawing,
    required this.color,
    required this.width,
    required this.onColor,
    required this.onWidth,
  });

  final InkDrawing drawing;
  final Color color;
  final double width;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: ListenableBuilder(
        listenable: drawing,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ColorDot(
                  color: InkColors.blue,
                  label: 'Blu',
                  selected: color == InkColors.blue,
                  onTap: () => onColor(InkColors.blue),
                ),
                _ColorDot(
                  color: InkColors.black,
                  label: 'Nero',
                  selected: color == InkColors.black,
                  onTap: () => onColor(InkColors.black),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.line_weight, size: 20),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Slider(
                      value: width,
                      min: 1.5,
                      max: 7,
                      label: 'Spessore',
                      semanticFormatterCallback: (v) => 'Spessore ${v.toStringAsFixed(1)}',
                      onChanged: onWidth,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Annulla',
                  onPressed: drawing.canUndo ? drawing.undo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Ripeti',
                  onPressed: drawing.canRedo ? drawing.redo : null,
                  icon: const Icon(Icons.redo),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: drawing.isEmpty ? null : drawing.clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Cancella'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label, required this.selected, required this.onTap});

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Inchiostro $label',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.accent : c.line, width: selected ? 3 : 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes, {required this.showHint});

  final List<InkStroke> strokes;
  final bool showHint;

  @override
  void paint(Canvas canvas, Size size) {
    // Linea guida su cui firmare.
    final y = size.height * 0.72;
    canvas.drawLine(
      Offset(size.width * 0.08, y),
      Offset(size.width * 0.92, y),
      Paint()
        ..color = const Color(0xFFD5D9E0)
        ..strokeWidth = 1,
    );
    if (showHint) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Firma qui',
          style: TextStyle(color: Color(0xFF9AA1AD), fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width * 0.08, y - tp.height - 8));
    }
    paintStrokes(canvas, strokes);
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}
