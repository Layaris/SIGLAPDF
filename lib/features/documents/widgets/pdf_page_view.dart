import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../editor/page_renderer.dart';

/// Immagine di una pagina renderizzata alla risoluzione adatta alla larghezza mostrata.
class PdfPageImage extends StatefulWidget {
  const PdfPageImage({
    super.key,
    required this.renderer,
    required this.page,
    required this.widthPts,
  });

  final PageRenderer renderer;
  final int page;

  /// Larghezza visiva della pagina in punti PDF.
  final double widthPts;

  @override
  State<PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<PdfPageImage> {
  ui.Image? _image;
  double _requested = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _image = widget.renderer.cached(widget.page);
  }

  void _ensure(double widthPx) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // dpi necessari per avere un pixel immagine per pixel fisico, con un tetto.
    final dpi = (widthPx * dpr / widget.widthPts * 72).clamp(48.0, 220.0);
    final bucket = (dpi / 24).ceil() * 24.0;
    if (bucket <= _requested) return;
    _requested = bucket;
    widget.renderer.render(widget.page, bucket).then((img) {
      if (!mounted) return;
      if (img != null) {
        setState(() {
          _image = img;
          _failed = false;
        });
      } else if (_image == null) {
        // Niente spinner infinito: l'anteprima manca ma gli elementi si possono comunque posizionare.
        setState(() => _failed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      _ensure(constraints.maxWidth);
      final img = _image;
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: c.line)),
        child: img == null && _failed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, color: c.secondary),
                    const SizedBox(height: 8),
                    Text('Anteprima non disponibile', style: TextStyle(color: c.secondary)),
                  ],
                ),
              )
            : img == null
            ? Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.secondary),
                ),
              )
            : RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
      );
    });
  }
}
