import 'package:flutter/material.dart';

import '../documents/documents_page.dart';
import '../profile/profile_page.dart';
import '../settings/settings_page.dart';
import '../signatures/signatures_page.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Documenti', Icons.description_outlined, Icons.description),
  _Destination('Firme', Icons.draw_outlined, Icons.draw),
  _Destination('Profilo', Icons.person_outline, Icons.person),
  _Destination('Impostazioni', Icons.settings_outlined, Icons.settings),
];

/// Navigazione principale: barra in basso su telefono, rail laterale su tablet e desktop.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  static HomeShellState? maybeOf(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  int get index => _index;

  void select(int i) => setState(() => _index = i);

  Widget _page(int i) => switch (i) {
        0 => const DocumentsPage(),
        1 => const SignaturesPage(),
        2 => const ProfilePage(),
        _ => const SettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(
      index: _index,
      children: [for (var i = 0; i < _destinations.length; i++) _page(i)],
    );

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }

    final extended = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: select,
            extended: extended,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                header: true,
                child: Text('Sigla', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
