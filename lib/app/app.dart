import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ui/core/app_theme.dart';
import 'app_configuration.dart';
import 'app_shell.dart';

class ZfHelperApp extends StatelessWidget {
  const ZfHelperApp({required this.configuration, super.key});

  final AppConfiguration configuration;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ZFHelper',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.build(Brightness.light),
    darkTheme: AppTheme.build(Brightness.dark),
    themeMode: ThemeMode.system,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemOverlayStyle(Theme.of(context).brightness),
      child: child!,
    ),
    home: AppShell(configuration: configuration),
  );
}
