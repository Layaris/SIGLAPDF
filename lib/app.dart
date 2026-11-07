import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_services.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_shell.dart';

class SiglaApp extends StatefulWidget {
  const SiglaApp({super.key, required this.services, this.navigatorKey});

  final AppServices services;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<SiglaApp> createState() => _SiglaAppState();
}

class _SiglaAppState extends State<SiglaApp> {
  late final AppLifecycleListener _lifecycle;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    // Le firme si richiudono quando l'app resta in background (vedi SignatureLock.grace).
    _lifecycle = AppLifecycleListener(onHide: services.lock.onHidden, onShow: services.lock.onShown);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'Sigla',
          navigatorKey: widget.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: services.settings.value.themeMode,
          locale: const Locale('it', 'IT'),
          supportedLocales: const [Locale('it', 'IT')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomeShell(),
        ),
      ),
    );
  }
}
