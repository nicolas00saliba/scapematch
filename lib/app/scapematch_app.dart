import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/router.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/pwa/pwa_frame.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';

class ScapeMatchApp extends ConsumerWidget {
  const ScapeMatchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeChoice = ref.watch(themeChoiceProvider);
    return MaterialApp.router(
      title: 'ScapeMatch',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeChoice.mode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeInOutCubic,
      builder: (context, child) {
        // No celular, a abertura cobre o primeiro frame. O site largo segue.
        return SplashGate(
          child: PwaFrame(child: child ?? const SizedBox.shrink()),
        );
      },
      routerConfig: router,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
