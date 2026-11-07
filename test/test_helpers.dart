import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/theme/app_theme.dart';

Widget wrapWithServices(AppServices services, Widget child) => AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('it', 'IT'),
        supportedLocales: const [Locale('it', 'IT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    );

/// PNG valido 4×2 con un pixel blu.
Uint8List tinyPng() {
  final im = img.Image(width: 4, height: 2, numChannels: 4);
  im.setPixelRgba(1, 1, 30, 60, 200, 255);
  return Uint8List.fromList(img.encodePng(im));
}
