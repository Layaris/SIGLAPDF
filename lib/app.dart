import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_services.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_shell.dart';

class SiglaApp extends StatefulWidget {
  const SiglaApp({super.key, required this.services, this.navigatorKey});

  final AppServices services;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<SiglaApp> createState() => _SiglaAppState();
}

class _SiglaAppState extends State<SiglaApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    // Le firme si richiudono quando l'app resta in background (vedi SignatureLock.grace).
    _lifecycle = AppLifecycleListener(onHide: services.lock.onHidden, onShow: services.lock.onShown);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Lingua "Sistema": se si cambia la lingua del telefono, l'app la segue subito.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted && services.settings.value.language == 'system') setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) {
          // Lingua: cambiarla ricostruisce tutta l'app (chiave sul MaterialApp).
          final lang = L10n.resolve(
            services.settings.value.language,
            ui.PlatformDispatcher.instance.locale.languageCode,
          );
          L10n.lang = lang;
          return MaterialApp(
            key: ValueKey('app-$lang'),
            title: 'Sigla',
            navigatorKey: widget.navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: services.settings.value.themeMode,
            locale: lang == 'en' ? const Locale('en') : const Locale('it', 'IT'),
            supportedLocales: const [Locale('it', 'IT'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
