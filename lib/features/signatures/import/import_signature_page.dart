import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/signature_processing.dart';
import '../signature_model.dart';
import '../widgets/save_signature_dialog.dart';

/// Da dove prendere l'immagine.
enum ImageOrigin { gallery, camera, file }

/// Import di una firma da immagine con scontorno automatico e soglia regolabile.
class ImportSignaturePage extends StatefulWidget {
  const ImportSignaturePage({super.key, required this.kind, required this.origin, this.initialBytes});

  final SignatureKind kind;
  final ImageOrigin origin;

  /// Per i test: immagine già caricata.
  final Uint8List? initialBytes;

  @override
  State<ImportSignaturePage> createState() => _ImportSignaturePageState();
}

class _ImportSignaturePageState extends State<ImportSignaturePage> {
  Uint8List? _source;
  CutoutResult? _result;
  String? _error;
  bool _busy = false;
  bool _picking = true;
  int? _threshold; // null = automatica
  InkRecolor _recolor = InkRecolor.original;
  Timer? _debounce;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialBytes != null) {
      _picking = false;
      _source = widget.initialBytes;
      _process();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    Uint8List? bytes;
    try {
      switch (widget.origin) {
        case ImageOrigin.file:
          bytes = (await AppScope.of(context).files.pickImage())?.bytes;
        case ImageOrigin.gallery:
        case ImageOrigin.camera:
          final x = await ImagePicker().pickImage(
            source: widget.origin == ImageOrigin.camera ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 2400,
            maxHeight: 2400,
          );
          bytes = await x?.readAsBytes();
      }
    } catch (e) {
      _error = 'Impossibile aprire l\'immagine.';
    }
    if (!mounted) return;
    if (bytes == null) {
      if (_source == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _picking = false);
      return;
    }
    setState(() {
      _picking = false;
      _source = bytes;
      _threshold = null;
    });
    await _process();
  }

  Future<void> _process() async {
    final src = _source;
    if (src == null) return;
    final job = ++_job;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = CutoutRequest(src, threshold: _threshold, recolor: _recolor, maxSide: 1400);
      final res = kIsWeb ? cutoutSignature(req) : await compute(cutoutSignature, req);
      if (!mounted || job != _job) return;
      setState(() {
        _result = res;
        _threshold ??= res.threshold;
      });
    } on SignatureProcessingException catch (e) {
      if (mounted && job == _job) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && job == _job) setState(() => _error = 'Immagine non valida.');
    } finally {
      if (mounted && job == _job) setState(() => _busy = false);
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _process);
  }

  Future<void> _save() async {
    final r = _result;
    if (r == null) return;
    final repo = AppScope.of(context).signatures;
    final name = await showSaveSignatureDialog(context, kind: widget.kind, existingCount: repo.ofKind(widget.kind).length);
    if (name == null || !mounted) return;
    await repo.add(name: name, kind: widget.kind, source: SignatureSource.image, png: r.png, width: r.width, height: r.height);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importa da immagine'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _result != null && !_busy ? _save : null, child: const Text('Salva')),
          ),
        ],
      ),
      body: SafeArea(
        child: _picking && _source == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AspectRatio(
                    aspectRatio: 2.4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: _CheckerPainter(),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: c.line),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(16),
                          alignment: Alignment.center,
                          child: _error != null
                              ? Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger))
                              : _result == null
                                  ? const CircularProgressIndicator()
                                  : Image.memory(
                                      _result!.png,
                                      gaplessPlayback: true,
                                      fit: BoxFit.contain,
                                      semanticLabel: 'Anteprima della firma scontornata',
                                    ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4, child: _busy ? const LinearProgressIndicator() : null),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Soglia', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() => _threshold = null);
                          _process();
                        },
                        child: const Text('Automatica'),
                      ),
                    ],
                  ),
                  Slider(
                    value: (_threshold ?? 128).toDouble(),
                    min: 20,
                    max: 240,
                    divisions: 220,
                    label: '${_threshold ?? 128}',
                    semanticFormatterCallback: (v) => 'Soglia ${v.round()}',
                    onChanged: _source == null
                        ? null
                        : (v) {
                            setState(() => _threshold = v.round());
                            _schedule();
                          },
                  ),
                  Text(
                    'Sposta a destra se la firma è troppo chiara, a sinistra se resta lo sfondo.',
                    style: TextStyle(color: c.secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Text('Colore', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<InkRecolor>(
                    segments: const [
                      ButtonSegment(value: InkRecolor.original, label: Text('Originale')),
                      ButtonSegment(value: InkRecolor.blue, label: Text('Blu')),
                      ButtonSegment(value: InkRecolor.black, label: Text('Nero')),
                    ],
                    selected: {_recolor},
                    onSelectionChanged: (s) {
                      setState(() => _recolor = s.first);
                      _process();
                    },
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Scegli un\'altra immagine'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Consiglio: firma su carta bianca con una penna scura e fotografa con buona luce.',
                    style: TextStyle(color: c.secondary, fontSize: 13),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Scacchiera chiara per mostrare la trasparenza.
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFFF0F2F5);
    const s = 12.0;
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = ((y / s).floor().isEven ? 0.0 : s); x < size.width; x += s * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}
