import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/page_frame.dart';
import '../../services/document_sources.dart';
import '../../services/images_to_pdf.dart';
import 'editor/editor_page.dart';

/// Punto di partenza: apri un PDF da firmare o compilare.
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  bool _busy = false;

  Future<void> _openPdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await AppScope.of(context).files.pickPdf();
      if (picked == null || !mounted) return;
      await openPdfEditor(context, name: picked.name, bytes: picked.bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile aprire il file.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Documenti')),
      body: PageFrame(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Firma o compila un PDF', style: t.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Apri un documento, aggiungi firma, sigla, testo o data, poi esporta il PDF. Il file non lascia il dispositivo.',
              style: t.bodyMedium?.copyWith(color: c.secondary),
            ),
            const SizedBox(height: 24),
            _ActionCard(
              icon: Icons.file_open_outlined,
              title: 'Apri PDF',
              subtitle: 'Scegli un file dal dispositivo',
              primary: true,
              busy: _busy,
              onTap: _openPdf,
            ),
            ...extraActions(context),
          ],
        ),
      ),
    );
  }

  static const _scanner = DocumentScanner();

  String _stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
  }

  Future<void> _fromImages(Future<List<Uint8List>> Function() source, String prefix) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final images = await source();
      if (images.isEmpty || !mounted) return;
      final pdf = await imagesToPdf(images);
      if (!mounted) return;
      await openPdfEditor(context, name: '$prefix-${_stamp()}.pdf', bytes: pdf);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossibile creare il PDF dalle immagini.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> extraActions(BuildContext context) => [
        if (_scanner.isSupported)
          _ActionCard(
            icon: Icons.document_scanner_outlined,
            title: 'Scansiona documento',
            subtitle: 'Foto con correzione della prospettiva',
            busy: _busy,
            onTap: () => _fromImages(_scanner.scan, 'scansione'),
          ),
        _ActionCard(
          icon: Icons.photo_library_outlined,
          title: 'Da immagini',
          subtitle: 'Trasforma foto o immagini in un PDF',
          busy: _busy,
          onTap: () => _fromImages(() async {
            final files = await AppScope.of(context).files.pickImages();
            return [for (final f in files) f.bytes];
          }, 'immagini'),
        ),
      ];
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = primary ? Theme.of(context).colorScheme.onPrimary : c.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: primary ? c.accent : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: primary ? BorderSide.none : BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: primary ? fg.withValues(alpha: 0.85) : c.secondary)),
                    ],
                  ),
                ),
                if (busy)
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                else
                  Icon(Icons.chevron_right, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
