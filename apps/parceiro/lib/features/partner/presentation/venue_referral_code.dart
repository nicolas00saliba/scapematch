import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Código da casa para compartilhar. Na demonstração é um exemplo.
///
/// Com [venueId], lê o código daquela unidade. Login com mais de uma unidade
/// vê o código da que está aberta.
class VenueReferralCode extends ConsumerStatefulWidget {
  const VenueReferralCode({super.key, this.venueId, this.singleUnit = true});

  final String? venueId;

  /// Login com uma unidade só: o RPC antigo devolve o código certo.
  final bool singleUnit;

  @override
  ConsumerState<VenueReferralCode> createState() => _VenueReferralCodeState();
}

class _VenueReferralCodeState extends ConsumerState<VenueReferralCode> {
  String? _code;
  var _loading = false;
  var _failed = false;

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
        final data = await loadVenueReferralCode(
          widget.venueId,
          singleUnit: widget.singleUnit,
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _code = data is String && data.isNotEmpty ? data : null;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
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
        else if (_failed)
          Text(
            venueReferralCodeError,
            key: PartnerKeys.venueReferralCodeError,
            style: TextStyle(color: theme.colorScheme.error),
          )
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

const venueReferralCodeError =
    'Não foi possível carregar o código desta unidade. Abra o painel de novo.';

/// Código de indicação da unidade [venueId].
///
/// O RPC com `p_venue_id` confere que a unidade é do login. Só cai no RPC
/// antigo (que devolve o código da unidade mais nova do login) quando o novo
/// não existe no banco (`PGRST202`) ou quando o login tem uma unidade só.
/// Em qualquer outro erro, lança: a tela mostra erro, nunca o código de outra
/// unidade.
Future<Object?> loadVenueReferralCode(
  String? venueId, {
  bool singleUnit = true,
  Future<Object?> Function(String fn, Map<String, Object?>? params)? rpc,
}) async {
  final call =
      rpc ??
      (String fn, Map<String, Object?>? params) =>
          scapeSupabase.rpc<Object?>(fn, params: params);
  if (venueId == null || venueId.isEmpty) {
    return call('my_venue_referral_code', null);
  }
  try {
    return await call('my_venue_referral_code', {'p_venue_id': venueId});
  } on PostgrestException catch (error) {
    if (error.code == 'PGRST202' || singleUnit) {
      return call('my_venue_referral_code', null);
    }
    rethrow;
  } on Object {
    if (singleUnit) return call('my_venue_referral_code', null);
    rethrow;
  }
}
