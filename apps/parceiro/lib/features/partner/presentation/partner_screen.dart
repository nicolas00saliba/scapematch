import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_home_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_login_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';

/// Sem sessão, o login da casa. Com sessão, o painel.
class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(partnerSessionProvider);
    if (session == null) {
      return const PartnerLoginScreen();
    }
    final desk = ref.watch(partnerDeskProvider);
    return desk.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(PartnerMessages.couldNotOpen),
              const SizedBox(height: 12),
              FilledButton(
                key: AppKeys.retry,
                onPressed: () => ref.invalidate(partnerDeskProvider),
                child: const Text(PartnerMessages.retry),
              ),
            ],
          ),
        ),
      ),
      data: (snapshot) {
        if (snapshot == null) {
          return const PartnerLoginScreen();
        }
        return PartnerHome(snapshot: snapshot);
      },
    );
  }
}
