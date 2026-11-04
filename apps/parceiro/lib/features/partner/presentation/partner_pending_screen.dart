import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerPendingScreen extends ConsumerWidget {
  const PartnerPendingScreen({super.key, required this.rejected});

  final bool rejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(partnerSessionProvider);
    final theme = Theme.of(context);
    return AppScaffold(
      desktopMaxWidth: 560,
      body: ListView(
        key: PartnerKeys.partnerPending,
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
        children: [
          Text(
            rejected
                ? PartnerMessages.rejectedTitle
                : PartnerMessages.awaitingTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            rejected
                ? PartnerMessages.rejectedBody
                : PartnerMessages.awaitingBody,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
          ),
          if (session != null && session.houseName.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              session.houseName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => ref.read(partnerSessionProvider.notifier).reload(),
            child: const Text(PartnerMessages.refresh),
          ),
          if (rejected) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PartnerVenueScreen(),
                  ),
                );
              },
              child: const Text(PartnerMessages.anotherVenue),
            ),
          ],
          TextButton(
            onPressed: () =>
                ref.read(partnerSessionProvider.notifier).signOut(),
            child: const Text(PartnerMessages.signOut),
          ),
        ],
      ),
    );
  }
}
