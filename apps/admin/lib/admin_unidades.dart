import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_confirm.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cidade do mesmo dono com conta PagBank conectada, que pode emprestar a
/// conta para esta.
class AdminShareSource {
  const AdminShareSource({
    required this.venueId,
    required this.venueName,
    required this.cityName,
    required this.accountLast4,
  });

  final String venueId;
  final String venueName;
  final String cityName;
  final String accountLast4;

  String get label {
    final city = cityName.isEmpty ? venueName : '$cityName ($venueName)';
    return accountLast4.isEmpty ? city : '$city · conta final $accountLast4';
  }
}

/// Estado de unidade de uma casa no Admin: removida pelo dono ou pelo Admin,
/// conta PagBank compartilhada e de quais cidades dá para compartilhar.
class AdminUnitState {
  const AdminUnitState({
    required this.deactivated,
    required this.deactivatedByOwner,
    required this.hasAccount,
    required this.sharedFromName,
    required this.sources,
  });

  final bool deactivated;
  final bool deactivatedByOwner;
  final bool hasAccount;
  final String? sharedFromName;
  final List<AdminShareSource> sources;

  static AdminUnitState fromJson(Object? raw) {
    final row = raw is Map ? raw : const {};
    final list = row['share_sources'];
    String text(Object? value) => value == null ? '' : '$value';
    return AdminUnitState(
      deactivated: row['deactivated'] == true,
      deactivatedByOwner: row['deactivated_by_owner'] == true,
      hasAccount: row['has_account'] == true,
      sharedFromName: row['shared_from_name'] is String
          ? row['shared_from_name'] as String
          : null,
      sources: [
        if (list is List)
          for (final item in list)
            if (item is Map && item['venue_id'] is String)
              AdminShareSource(
                venueId: item['venue_id'] as String,
                venueName: text(item['venue_name']),
                cityName: text(item['city_name']),
                accountLast4: text(item['account_last4']),
              ),
      ],
    );
  }
}

abstract class AdminUnitsApi {
  Future<AdminUnitState> state(String venueId);
  Future<void> share(String venueId, String sourceVenueId);
  Future<void> reactivate(String venueId);
}

class SupabaseAdminUnitsApi implements AdminUnitsApi {
  SupabaseAdminUnitsApi(this.client);

  final SupabaseClient client;

  @override
  Future<AdminUnitState> state(String venueId) async => AdminUnitState.fromJson(
    await _rpc('admin_venue_units', {'p_venue_id': venueId}),
  );

  @override
  Future<void> share(String venueId, String sourceVenueId) async {
    await _rpc('admin_share_venue_pagbank_account', {
      'p_venue_id': venueId,
      'p_source_venue_id': sourceVenueId,
    });
  }

  @override
  Future<void> reactivate(String venueId) async {
    await _rpc('admin_reactivate_unit', {'p_venue_id': venueId});
  }

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      throw AdminRejected(error.message);
    }
  }
}

final adminUnitsApiProvider = Provider<AdminUnitsApi>((ref) {
  if (!scapeUsesLiveBackend) {
    throw StateError('O Admin real ainda não ligou o Supabase.');
  }
  return SupabaseAdminUnitsApi(scapeSupabase);
});

/// Cartão da casa: reativar cidade removida e compartilhar a conta PagBank
/// de outra cidade do mesmo dono. Some quando não há nada a fazer ou quando
/// o servidor não responde.
class AdminUnitsCard extends ConsumerStatefulWidget {
  const AdminUnitsCard({super.key, required this.venueId, this.onChanged});

  final String venueId;
  final VoidCallback? onChanged;

  @override
  ConsumerState<AdminUnitsCard> createState() => _AdminUnitsCardState();
}

class _AdminUnitsCardState extends ConsumerState<AdminUnitsCard> {
  AdminUnitState? _state;
  String? _message;
  var _error = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await ref.read(adminUnitsApiProvider).state(widget.venueId);
      if (!mounted) return;
      setState(() => _state = state);
    } on Object {
      if (!mounted) return;
      setState(() => _state = null);
    }
  }

  Future<void> _act(
    String title,
    String body,
    String word,
    Future<void> Function(AdminUnitsApi api) write,
    String done,
  ) async {
    final ok = await confirmTyped(
      context,
      title: title,
      body: '$body\n\nDigite $word para confirmar.',
      word: word,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await write(ref.read(adminUnitsApiProvider));
      await _load();
      if (!mounted) return;
      setState(() {
        _message = done;
        _error = false;
      });
      widget.onChanged?.call();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _message = adminErrorText(error);
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox.shrink();
    final showShare = !state.hasAccount && state.sources.isNotEmpty;
    if (!state.deactivated &&
        !showShare &&
        state.sharedFromName == null &&
        _message == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      key: const Key('admin-unidades'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cidades da casa', style: theme.textTheme.titleMedium),
            if (state.sharedFromName != null)
              Text(
                'Recebe pela conta PagBank de ${state.sharedFromName}. A nota sai pelo CNPJ dessa conta.',
              ),
            if (state.deactivated) ...[
              Text(
                state.deactivatedByOwner
                    ? 'Cidade removida pelo dono. Não aparece para o jogador.'
                    : 'Cidade removida pelo suporte. Não aparece para o jogador.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const Key('admin-reativar-cidade'),
                  onPressed: _busy
                      ? null
                      : () => _act(
                          'Reativar esta cidade?',
                          'Volta como estava: aprovada volta para o jogador, em análise continua em análise. Se estava suspensa antes da remoção, continua suspensa.',
                          'REATIVAR',
                          (api) => api.reactivate(widget.venueId),
                          'Cidade reativada.',
                        ),
                  child: const Text('Reativar cidade'),
                ),
              ),
            ],
            if (showShare) ...[
              const Text(
                'Usar a mesma conta PagBank de outra cidade do dono. Os pagamentos desta cidade caem na conta escolhida e a nota sai pelo CNPJ dela.',
              ),
              for (final source in state.sources)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: Key('admin-compartilhar-${source.venueId}'),
                    onPressed: _busy
                        ? null
                        : () => _act(
                            'Usar a conta de ${source.venueName}?',
                            'Esta cidade passa a receber pela conta PagBank de ${source.label}. A nota fiscal sai pelo CNPJ dessa conta.',
                            'COMPARTILHAR',
                            (api) => api.share(widget.venueId, source.venueId),
                            'Conta PagBank compartilhada.',
                          ),
                    child: Text('Usar a conta de ${source.label}'),
                  ),
                ),
            ],
            if (_message != null)
              Text(
                _message!,
                key: const Key('admin-unidades-aviso'),
                style: TextStyle(
                  color: _error ? theme.colorScheme.error : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
