import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ink_illustrations.dart';
import '../../core/widgets/page_frame.dart';
import '../../services/document_sources.dart';
import '../../services/images_to_pdf.dart';
import 'editor/editor_page.dart';
import 'recents/recents_repository.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final hero = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Firma o compila\nun PDF', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.1)),
              const SizedBox(height: 6),
              SizedBox(height: 34, width: 190, child: SignatureFlourish(color: c.accent, strokeWidth: 2.6)),
              const SizedBox(height: 10),
              Text(
                'Aggiungi firma, sigla, testo e data, compila i moduli dal tuo profilo ed esporta il PDF.',
                style: t.bodyMedium?.copyWith(color: c.secondary, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Transform.rotate(angle: 0.06, child: SignedSheetIllustration(size: wide ? const Size(132, 166) : const Size(96, 122))),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Documenti')),
      body: PageFrame(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            hero,
            const SizedBox(height: 28),
            _ActionCard(
              icon: Icons.file_open_outlined,
              title: 'Apri PDF',
              subtitle: 'Scegli un file dal dispositivo',
              primary: true,
              busy: _busy,
              onTap: _openPdf,
            ),
            ...extraActions(context),
            _RecentsSection(onOpen: (d) => openPdfEditor(context, name: d.name, bytes: d.pdf)),
            const SizedBox(height: 20),
            Text('Come funziona', style: t.titleMedium),
            const SizedBox(height: 12),
            const _Steps(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: c.success, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tutto resta su questo dispositivo: nessun account, nessun cloud.',
                      style: TextStyle(color: c.ink, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
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

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const steps = [
      ('Apri', 'un PDF, una scansione o delle foto'),
      ('Firma', 'e compila: trascina, ridimensiona, conferma'),
      ('Esporta', 'il PDF e salvalo o condividilo'),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                StepDot(i + 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: steps[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: ' ${steps[i].$2}', style: TextStyle(color: c.secondary)),
                  ])),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ultimi PDF esportati: tocca per riaprire, menu per condividere, salvare, eliminare.
class _RecentsSection extends StatelessWidget {
  const _RecentsSection({required this.onOpen});
  final void Function(RecentDocument d) onOpen;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final repo = services.recents;
    return ListenableBuilder(
      listenable: Listenable.merge([repo, services.settings]),
      builder: (context, _) {
        if (repo.isEmpty || !services.settings.value.keepRecents) return const SizedBox.shrink();
        final c = AppColors.of(context);
        final t = Theme.of(context).textTheme;
        final fmt = DateFormat('d MMM yyyy, HH:mm', 'it_IT');
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text('Recenti', style: t.titleMedium))),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Cancellare i recenti?'),
                          content: const Text('I PDF esportati vengono tolti da questo elenco. I file salvati altrove restano.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancella')),
                          ],
                        ),
                      );
                      if (ok == true) await repo.clear();
                    },
                    child: const Text('Cancella'),
                  ),
                ],
              ),
              Card(
                child: Column(
                  children: [
                    for (final (i, d) in repo.all.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 76, color: c.line),
                      ListTile(
                        onTap: () => onOpen(d),
                        leading: Container(
                          width: 44,
                          height: 58,
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: c.line)),
                          child: d.thumbnail == null
                              ? Icon(Icons.picture_as_pdf_outlined, color: c.secondary)
                              : Image.memory(d.thumbnail!, fit: BoxFit.cover, gaplessPlayback: true),
                        ),
                        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${fmt.format(d.savedAt)} · ${d.pageCount} ${d.pageCount == 1 ? 'pagina' : 'pagine'}',
                          style: TextStyle(color: c.secondary, fontSize: 13),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Opzioni',
                          onSelected: (a) async {
                            switch (a) {
                              case 'open':
                                onOpen(d);
                              case 'share':
                                await Printing.sharePdf(bytes: d.pdf, filename: d.name);
                              case 'save':
                                await services.files.save(fileName: d.name, bytes: d.pdf, mimeType: 'application/pdf');
                              case 'delete':
                                await repo.remove(d.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'open', child: Text('Apri')),
                            PopupMenuItem(value: 'share', child: Text('Condividi')),
                            PopupMenuItem(value: 'save', child: Text('Salva')),
                            PopupMenuItem(value: 'delete', child: Text('Togli dai recenti')),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
