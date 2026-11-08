import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_frame.dart';
import '../widgets/text_input_dialog.dart';

/// Elenco dei modelli salvati: rinomina ed elimina.
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).templates;
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Modelli'))),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => repo.isEmpty
            ? EmptyState(
                icon: Icons.dashboard_customize_outlined,
                title: tr('Nessun modello'),
                message: tr('Nell\'editor posiziona firma, testi e data, poi dal menu ⋮ scegli "Salva come modello". Quando riapri lo stesso modulo te lo propongo.'),
              )
            : PageFrame(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final t in repo.all)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.dashboard_customize_outlined),
                          title: Text(t.name),
                          subtitle: Text(
                            '${tr('{0} elementi', [t.elements.length])} · ${t.pageCount == 1 ? tr('1 pagina') : tr('{0} pagine', [t.pageCount])}${t.fingerprint == null ? tr(' · da applicare a mano') : ''}',
                            style: TextStyle(color: c.secondary),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: tr('Opzioni'),
                            onSelected: (a) async {
                              if (a == 'rename') {
                                final n = await showTextInputDialog(context, title: tr('Rinomina'), initial: t.name, action: tr('Salva'));
                                if (n != null) await repo.rename(t.id, n);
                              } else {
                                await repo.remove(t.id);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'rename', child: Text(tr('Rinomina'))),
                              PopupMenuItem(value: 'delete', child: Text(tr('Elimina'))),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
