import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/l10n/l10n.dart';
import '../../services/crypto_backup.dart';
import 'backup_service.dart';

/// Chiede una password (con conferma per l'esportazione).
Future<String?> askBackupPassword(BuildContext context, {required bool confirm}) =>
    showDialog<String>(context: context, builder: (_) => _PasswordDialog(confirm: confirm));

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (widget.confirm) {
      if (_a.text.length < CryptoBackup.minPasswordLength) {
        setState(() => _error = tr('Almeno {0} caratteri.', [CryptoBackup.minPasswordLength]));
        return;
      }
      if (_a.text != _b.text) {
        setState(() => _error = tr('Le password non coincidono.'));
        return;
      }
    } else if (_a.text.isEmpty) {
      return;
    }
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.confirm ? tr('Proteggi il backup') : tr('Password del backup')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.confirm)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr('Senza questa password il backup non si può aprire. Conservala con cura.')),
              ),
            TextField(
              controller: _a,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('Password'),
                suffixIcon: IconButton(
                  tooltip: _obscure ? tr('Mostra') : tr('Nascondi'),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => widget.confirm ? null : _ok(),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _b,
                obscureText: _obscure,
                decoration: InputDecoration(labelText: tr('Ripeti la password')),
                onSubmitted: (_) => _ok(),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annulla'))),
          FilledButton(onPressed: _ok, child: Text(widget.confirm ? tr('Esporta') : tr('Apri'))),
        ],
      );
}

Future<void> _withProgress(BuildContext context, String text, Future<void> Function() job) async {
  final nav = Navigator.of(context);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Text(text)])),
    ),
  ));
  try {
    await job();
  } finally {
    nav.pop();
  }
}

/// Esporta il backup cifrato e lo salva con il dialogo di sistema.
Future<void> exportBackupFlow(BuildContext context) async {
  final services = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final password = await askBackupPassword(context, confirm: true);
  if (password == null || !context.mounted) return;
  final service = BackupService(services);
  try {
    late final Uint8List bytes;
    await _withProgress(context, tr('Cifro il backup…'), () async => bytes = await service.export(password));
    final ok = await services.files.save(fileName: service.fileName(), bytes: bytes, mimeType: 'application/octet-stream');
    if (ok) messenger.showSnackBar(SnackBar(content: Text(tr('Backup salvato'))));
  } on BackupException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Backup non riuscito.'))));
  }
}

/// Importa un backup scegliendo tra unisci e sostituisci.
Future<void> importBackupFlow(BuildContext context) async {
  final services = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Su Android un filtro su un'estensione sconosciuta può nascondere il file: si sceglie qualsiasi file.
  final picked = await services.files.pickAny(extensions: kIsWeb ? const ['sigla'] : null);
  if (picked == null || !context.mounted) return;
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Come importare?')),
      content: Text(
        tr('Unisci aggiunge le firme mancanti e completa i campi vuoti del profilo.\nSostituisci cancella firme, profilo e impostazioni di questo dispositivo e usa quelli del backup.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annulla'))),
        OutlinedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Sostituisci'))),
        FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Unisci'))),
      ],
    ),
  );
  if (replace == null || !context.mounted) return;
  final password = await askBackupPassword(context, confirm: false);
  if (password == null || !context.mounted) return;
  try {
    late final ImportSummary summary;
    await _withProgress(
      context,
      tr('Apro il backup…'),
      () async => summary = await BackupService(services).import(picked.bytes, password, replace: replace),
    );
    messenger.showSnackBar(SnackBar(
      content: Text(summary.signatures == 1 ? tr('Backup importato: 1 firma') : tr('Backup importato: {0} firme', [summary.signatures])),
    ));
  } on BackupException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Importazione non riuscita.'))));
  }
}
