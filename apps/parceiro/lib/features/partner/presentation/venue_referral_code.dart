import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Código da casa para compartilhar. Na demonstração é um exemplo.
///
/// Com [venueId], lê o código daquela unidade. Login com mais de uma unidade
/// vê o código da que está aberta.
class VenueReferralCode extends ConsumerStatefulWidget {
  const VenueReferralCode({super.key, this.venueId});

  final String? venueId;

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
        final data = await loadVenueReferralCode(widget.venueId);
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

/// Código de indicação da unidade [venueId].
///
/// O RPC com `p_venue_id` confere que a unidade é do login. Enquanto a
/// migration que cria esse RPC não estiver no banco, cai no RPC antigo, que
/// devolve o código da unidade mais nova do login.
Future<Object?> loadVenueReferralCode(
  String? venueId, {
  Future<Object?> Function(String fn, Map<String, Object?>? params)? rpc,
}) async {
  final call =
      rpc ??
      (String fn, Map<String, Object?>? params) =>
          scapeSupabase.rpc<Object?>(fn, params: params);
  if (venueId != null && venueId.isNotEmpty) {
    try {
      return await call('my_venue_referral_code', {'p_venue_id': venueId});
    } on Object {
      // RPC novo ainda fora do banco: segue para o antigo.
    }
  }
  return call('my_venue_referral_code', null);
}
