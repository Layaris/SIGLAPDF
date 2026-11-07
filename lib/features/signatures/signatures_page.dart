import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import 'new_signature_sheet.dart';
import 'signature_model.dart';
import 'signature_repository.dart';
import 'widgets/save_signature_dialog.dart';
import 'widgets/signature_image.dart';

/// Libreria firme: le firme sono grandi e protagoniste.
class SignaturesPage extends StatelessWidget {
  const SignaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final repo = services.signatures;
    final lock = services.lock;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => lock.isLocked ? _Locked(onUnlock: lock.unlock) : _scaffold(context, repo),
    );
  }

  Widget _scaffold(BuildContext context, SignatureRepository repo) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firme')),
      floatingActionButton: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => repo.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => showNewSignatureSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Nuova firma'),
              ),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          if (repo.isEmpty) {
            return EmptyState(
              icon: Icons.gesture,
              title: 'Crea la tua firma',
              message: 'Disegnala, importala da una foto o scrivila. Resta solo su questo dispositivo.',
              actions: [
                FilledButton.icon(
                  onPressed: () => showNewSignatureSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuova firma'),
                ),
                OutlinedButton(
                  onPressed: () => showNewSignatureSheet(context, initialKind: SignatureKind.initials),
                  child: const Text('Nuova sigla'),
                ),
              ],
            );
          }
          return _Library(repo: repo);
        },
      ),
    );
  }
}

class _Library extends StatelessWidget {
  const _Library({required this.repo});
  final SignatureRepository repo;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 3 : (width >= 640 ? 2 : 1);
    final sections = [
      (SignatureKind.signature, 'Firme', repo.ofKind(SignatureKind.signature)),
      (SignatureKind.initials, 'Sigle', repo.ofKind(SignatureKind.initials)),
    ];
    return CustomScrollView(
      slivers: [
        for (final (kind, title, items) in sections) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium))),
                  TextButton.icon(
                    onPressed: () => showNewSignatureSheet(context, initialKind: kind),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(kind == SignatureKind.initials ? 'Nuova sigla' : 'Nuova firma'),
                  ),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  kind == SignatureKind.initials
                      ? 'Nessuna sigla. Serve per siglare tutte le pagine in un tocco.'
                      : 'Nessuna firma.',
                  style: TextStyle(color: AppColors.of(context).secondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: kind == SignatureKind.initials ? 200 : 230,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => SignatureCard(signature: items[i], repo: repo),
                  childCount: items.length,
                ),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

enum _Action { rename, makeDefault, delete }

class SignatureCard extends StatelessWidget {
  const SignatureCard({super.key, required this.signature, required this.repo});

  final Signature signature;
  final SignatureRepository repo;

  Future<void> _onAction(BuildContext context, _Action a) async {
    switch (a) {
      case _Action.rename:
        final name = await showSaveSignatureDialog(
          context,
          kind: signature.kind,
          existingCount: 0,
          initial: signature.name,
          title: 'Rinomina',
        );
        if (name != null) await repo.rename(signature.id, name);
      case _Action.makeDefault:
        await repo.setDefault(signature.id);
      case _Action.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Eliminare "${signature.name}"?'),
            content: const Text("L'eliminazione non si può annullare."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.of(context).danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Elimina'),
              ),
            ],
          ),
        );
        if (ok == true) await repo.remove(signature.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SignatureImage(signature: signature, padding: const EdgeInsets.all(20))),
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(signature.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                ),
                if (signature.isDefault)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: c.success),
                        const SizedBox(width: 4),
                        Text('Predefinita', style: TextStyle(color: c.success, fontSize: 13)),
                      ],
                    ),
                  ),
                PopupMenuButton<_Action>(
                  tooltip: 'Opzioni',
                  onSelected: (a) => _onAction(context, a),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: _Action.rename, child: Text('Rinomina')),
                    if (!signature.isDefault) const PopupMenuItem(value: _Action.makeDefault, child: Text('Imposta predefinita')),
                    const PopupMenuItem(value: _Action.delete, child: Text('Elimina')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.onUnlock});
  final Future<bool> Function() onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Firme')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Firme protette',
          message: 'Sblocca con impronta, volto o PIN per vedere e usare le tue firme.',
          actions: [
            FilledButton.icon(onPressed: onUnlock, icon: const Icon(Icons.lock_open), label: const Text('Sblocca')),
          ],
        ),
      );
}
