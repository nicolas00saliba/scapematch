import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Código da casa para compartilhar. Na demonstração é um exemplo.
class VenueReferralCode extends ConsumerStatefulWidget {
  const VenueReferralCode({super.key});

  @override
  ConsumerState<VenueReferralCode> createState() => _VenueReferralCodeState();
}

class _VenueReferralCodeState extends ConsumerState<VenueReferralCode> {
  String? _code;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    if (!scapeUsesLiveBackend) {
      _code = 'CASADEMO';
      return;
    }
    _loading = true;
    Future<void>(() async {
      try {
        final data = await scapeSupabase.rpc('my_venue_referral_code');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _code = data is String && data.isNotEmpty ? data : null;
        });
      } on Object {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return Column(
      key: PartnerKeys.venueReferralCode,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Código da casa',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (_loading)
          const LinearProgressIndicator()
        else if (code == null)
          const Text('O código aparece quando a casa estiver cadastrada.')
        else
          Row(
            children: [
              Expanded(child: Text('Compartilhe: $code')),
              IconButton(
                tooltip: 'Copiar código',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
        if (!scapeUsesLiveBackend)
          Text(
            'Exemplo. No app real este é o código da casa.',
            style: theme.textTheme.bodySmall,
          ),
        Text(venueReferralHint(ref.watch(rewardRulesProvider))),
      ],
    );
  }
}
