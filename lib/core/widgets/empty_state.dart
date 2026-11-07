import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Stato vuoto che invita ad agire.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: c.secondary),
              const SizedBox(height: 20),
              Text(title, style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: t.bodyMedium?.copyWith(color: c.secondary), textAlign: TextAlign.center),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
