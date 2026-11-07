import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Punto del tratto. [pressure] è normalizzata in 0–1, oppure null se il dispositivo
/// non la rileva (dito, mouse): in quel caso lo spessore dipende dalla velocità.
@immutable
class InkPoint {
  const InkPoint(this.x, this.y, {this.pressure, this.t = 0});

  final double x;
  final double y;
  final double? pressure;

  /// Millisecondi dall'inizio del tratto.
  final int t;

  Offset get offset => Offset(x, y);
}

@immutable
class InkStroke {
  const InkStroke(this.points, {required this.width, required this.color});

  final List<InkPoint> points;

  /// Spessore base in pixel logici.
  final double width;
  final Color color;

  InkStroke withPoint(InkPoint p) => InkStroke([...points, p], width: width, color: color);
}

/// Segmento pronto da disegnare: curva quadratica con spessore.
@immutable
class InkSegment {
  const InkSegment(this.start, this.control, this.end, this.width);
  final Offset start;
  final Offset control;
  final Offset end;
  final double width;
}

/// Trasforma un tratto in segmenti di Bezier quadratiche lisci (metodo dei punti medi)
/// con spessore variabile da pressione o velocità, filtrato per evitare scatti.
List<InkSegment> buildSegments(InkStroke stroke) {
  final pts = _dedupe(stroke.points);
  if (pts.isEmpty) return const [];
  final widths = _widths(pts, stroke.width);
  if (pts.length == 1) {
    final o = pts.first.offset;
    return [InkSegment(o, o, o, widths.first)];
  }
  if (pts.length == 2) {
    final a = pts[0].offset, b = pts[1].offset;
    return [InkSegment(a, Offset.lerp(a, b, 0.5)!, b, (widths[0] + widths[1]) / 2)];
  }
  final segments = <InkSegment>[];
  var start = pts[0].offset;
  for (var i = 1; i < pts.length - 1; i++) {
    final control = pts[i].offset;
    final end = Offset.lerp(control, pts[i + 1].offset, 0.5)!;
    segments.add(InkSegment(start, control, end, widths[i]));
    start = end;
  }
  final last = pts.last.offset;
  segments.add(InkSegment(start, Offset.lerp(start, last, 0.5)!, last, widths.last));
  return segments;
}

List<InkPoint> _dedupe(List<InkPoint> points) {
  final out = <InkPoint>[];
  for (final p in points) {
    if (out.isEmpty || (out.last.offset - p.offset).distance >= 0.5) out.add(p);
  }
  return out;
}

List<double> _widths(List<InkPoint> pts, double base) {
  final hasPressure = pts.any((p) => p.pressure != null);
  final raw = <double>[];
  for (var i = 0; i < pts.length; i++) {
    double factor;
    if (hasPressure) {
      final p = (pts[i].pressure ?? 0.5).clamp(0.0, 1.0);
      factor = 0.45 + 1.1 * p; // 0.45× … 1.55×
    } else if (i == 0) {
      factor = 1.0;
    } else {
      final d = (pts[i].offset - pts[i - 1].offset).distance;
      final dt = math.max(1, pts[i].t - pts[i - 1].t);
      final speed = d / dt; // px/ms
      factor = (1.25 - speed * 0.35).clamp(0.6, 1.25);
    }
    raw.add(base * factor);
  }
  // Filtro passa-basso: lo spessore cambia gradualmente.
  final smooth = <double>[raw.first];
  for (var i = 1; i < raw.length; i++) {
    smooth.add(smooth.last * 0.7 + raw[i] * 0.3);
  }
  return smooth;
}

/// Disegna i tratti su un canvas.
void paintStrokes(Canvas canvas, List<InkStroke> strokes, {double scale = 1, Offset shift = Offset.zero}) {
  for (final s in strokes) {
    final paint = Paint()
      ..color = s.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final seg in buildSegments(s)) {
      paint.strokeWidth = seg.width * scale;
      final a = (seg.start + shift) * scale, c = (seg.control + shift) * scale, b = (seg.end + shift) * scale;
      if ((a - b).distance < 0.01) {
        canvas.drawCircle(a, seg.width * scale / 2, Paint()..color = s.color);
        continue;
      }
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(c.dx, c.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }
}

/// Rettangolo che contiene tutti i tratti, compreso lo spessore massimo.
Rect? strokesBounds(List<InkStroke> strokes) {
  Rect? r;
  for (final s in strokes) {
    for (final p in s.points) {
      final pad = s.width * 1.6;
      final pr = Rect.fromCenter(center: p.offset, width: pad * 2, height: pad * 2);
      r = r == null ? pr : r.expandToInclude(pr);
    }
  }
  return r;
}

/// Disegno con cronologia per annulla/ripeti.
class InkDrawing extends ChangeNotifier {
  final List<InkStroke> _strokes = [];
  final List<InkStroke> _redo = [];
  InkStroke? _current;

  List<InkStroke> get strokes => [..._strokes, ?_current];
  bool get isEmpty => _strokes.isEmpty && _current == null;
  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void begin(InkPoint p, {required double width, required Color color}) {
    _current = InkStroke([p], width: width, color: color);
    notifyListeners();
  }

  void extend(InkPoint p) {
    final c = _current;
    if (c == null) return;
    _current = c.withPoint(p);
    notifyListeners();
  }

  void end() {
    final c = _current;
    if (c == null) return;
    _strokes.add(c);
    _current = null;
    _redo.clear();
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _redo.add(_strokes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _strokes.add(_redo.removeLast());
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty && _current == null) return;
    // Cancella resta annullabile: i tratti finiscono nella pila di ripeti al contrario.
    _redo
      ..clear()
      ..addAll(_strokes.reversed);
    _strokes.clear();
    _current = null;
    notifyListeners();
  }

  /// Cambia il colore di tutti i tratti (scelta blu/nero dopo aver disegnato).
  void recolor(Color color) {
    for (var i = 0; i < _strokes.length; i++) {
      final s = _strokes[i];
      _strokes[i] = InkStroke(s.points, width: s.width, color: color);
    }
    notifyListeners();
  }
}
