import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/pwa/pwa_frame.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch_parceiro/features/partner/data/mp_oauth_return.dart';
import 'package:scapematch_parceiro/features/partner/presentation/mp_return_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

class ParceiroApp extends ConsumerStatefulWidget {
  const ParceiroApp({super.key, this.initialUri});

  final Uri? initialUri;

  @override
  ConsumerState<ParceiroApp> createState() => _ParceiroAppState();
}

class _ParceiroAppState extends ConsumerState<ParceiroApp> {
  late final Uri _uri;
  var _mpReturn = false;

  @override
  void initState() {
    super.initState();
    _uri = widget.initialUri ?? Uri.base;
    _mpReturn = isMpOauthReturnPath(_uri);
  }

  void _leaveReturn() {
    ref.read(partnerSectionProvider.notifier).select(PartnerSection.balance);
    setState(() => _mpReturn = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeChoice = ref.watch(themeChoiceProvider);
    return MaterialApp(
      title: 'EscapeMatch Parceiro',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: themeChoice.mode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeInOutCubic,
      builder: (context, child) {
        // A mesma abertura do jogador: só no cold start do celular.
        return SplashGate(
          markImage: const AssetImage('assets/parceiro/logo_parceiro_pin.png'),
          curtain: ScapeLogo.markImageBackground,
          onDark: true,
          lockupFooterExtent: PartnerSealTrain.extentFor,
          lockupFooter: (context, height, absorb, {double fade = 0}) {
            return PartnerSealTrain(
              logoHeight: height,
              absorb: absorb,
              fade: fade,
              solidPeach: true,
            );
          },
          child: PwaFrame(child: child ?? const SizedBox.shrink()),
        );
      },
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _mpReturn
          ? MpReturnScreen(uri: _uri, onFinished: _leaveReturn)
          : const PartnerScreen(),
    );
  }
}
