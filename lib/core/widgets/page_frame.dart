import 'package:flutter/material.dart';

/// Limita la larghezza del contenuto su schermi larghi (tablet, desktop).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
