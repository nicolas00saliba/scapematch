import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/payments/data/pagbank_connect_return.dart';
import 'package:scapematch/features/payments/presentation/pagbank_connect_return_page.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/pwa/pwa_frame.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/auth/presentation/password_recovery_gate.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_sync.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_password_reset.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_screen.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

class _ParceiroHome extends StatefulWidget {
  const _ParceiroHome();

  @override
  State<_ParceiroHome> createState() => _ParceiroHomeState();
}

class _ParceiroHomeState extends State<_ParceiroHome> {
  PagbankConnectReturn? _hit;

  @override
  void initState() {
    super.initState();
    _hit = pendingPagbankConnectReturn;
    pendingPagbankConnectReturn = null;
  }

  @override
  Widget build(BuildContext context) {
    final hit = _hit;
    if (hit == null) return const PartnerScreen();
    return PagbankConnectReturnPage(
      hit: hit,
      complete: (item) async {
        final response = await scapeSupabase.functions.invoke(
          'pagbank-connect',
          body: {'code': item.code, 'state': item.state},
        );
        final data = response.data;
        return data is Map && data['linked'] == true;
      },
      onDone: () => setState(() => _hit = null),
    );
  }
}

/// Depois do link, grava a senha com `auth.updateUser` e abre a casa.
class PartnerPasswordRecovery extends ConsumerWidget {
  const PartnerPasswordRecovery({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PasswordRecoveryGate(
      savePassword: (password) async {
        final error = await updatePartnerPassword(password);
        if (error != null) return error;
        try {
          await ref.read(partnerSessionProvider.notifier).reload();
        } on Object {
          // A senha já foi salva. A casa relê quando o painel abre.
        }
        return null;
      },
      child: child,
    );
  }
}

class ParceiroApp extends ConsumerWidget {
  const ParceiroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          child: PartnerPasswordRecovery(
            child: RewardRulesSync(
              child: PwaFrame(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _ParceiroHome(),
    );
  }
}
