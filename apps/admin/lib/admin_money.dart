import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_confirm.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final adminMoneyProvider = Provider<AdminMoneyApi>((ref) {
  if (!scapeUsesLiveBackend) return MemoryAdminMoneyApi();
  return SupabaseAdminMoneyApi(scapeSupabase);
});

abstract class AdminMoneyApi {
  Future<MoneyPage> charges({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<MoneyPage> refunds({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<MoneyPage> withdrawals({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<MoneyCharge> charge(String id);
  Future<MoneyMove> refundCharge(String id, String confirm, {int? amountCents});
  Future<MoneyMove> reopenCustody(String id, String confirm);
  Future<MoneyMove> reopenCac(String id, String confirm);
  Future<void> settle(String groupId);
  Future<CacFlag> cacFlag();
}

class MoneyPage {
  const MoneyPage({required this.total, required this.rows});
  final int total;
  final List<Map<String, Object?>> rows;
}

class MoneyMove {
  const MoneyMove({
    required this.groupId,
    this.amountCents,
    this.groupReady = false,
  });
  final String groupId;
  final int? amountCents;
  final bool groupReady;
}

class CacFlag {
  const CacFlag({required this.readable, this.enabled});
  final bool readable;
  final bool? enabled;
}

class MoneyCharge {
  const MoneyCharge({
    required this.id,
    required this.groupId,
    required this.venueName,
    required this.playerName,
    required this.roomName,
    required this.startsAt,
    required this.status,
    required this.billingType,
    required this.amountCents,
    required this.chargedCents,
    required this.interestCents,
    required this.discountCents,
    required this.subsidyCents,
    required this.points,
    required this.houseCents,
    required this.divergence,
    required this.custody,
    required this.attempts,
    required this.groupClosed,
    required this.fullRefundCents,
    required this.queueStatus,
  });

  final String id;
  final String groupId;
  final String venueName;
  final String playerName;
  final String roomName;
  final DateTime? startsAt;
  final String status;
  final String billingType;
  final int amountCents;
  final int chargedCents;
  final int interestCents;
  final int discountCents;
  final int subsidyCents;
  final int points;
  final int houseCents;
  final String divergence;
  final String custody;
  final int attempts;
  final bool groupClosed;
  final int fullRefundCents;
  final String queueStatus;
}

class SupabaseAdminMoneyApi implements AdminMoneyApi {
  SupabaseAdminMoneyApi(this._client);
  final SupabaseClient _client;

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) {
    return _client.rpc(name, params: params);
  }

  MoneyPage _page(dynamic raw) {
    final row = raw is Map ? raw : const <String, dynamic>{};
    final rows = row['rows'];
    return MoneyPage(
      total: row['total'] is int
          ? row['total'] as int
          : int.tryParse('${row['total']}') ?? 0,
      rows: [
        for (final item in rows is List ? rows : const [])
          if (item is Map) Map<String, Object?>.from(item),
      ],
    );
  }

  @override
  Future<MoneyPage> charges({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _page(
    await _rpc('admin_search_charges', {
      'p_query': query,
      'p_status': status,
      'p_include_test': includeTest,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );

  @override
  Future<MoneyPage> refunds({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _page(
    await _rpc('admin_search_refund_queue', {
      'p_query': query,
      'p_status': status,
      'p_include_test': includeTest,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );

  @override
  Future<MoneyPage> withdrawals({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _page(
    await _rpc('admin_search_withdrawals', {
      'p_query': query,
      'p_status': status,
      'p_include_test': includeTest,
      'p_limit': limit,
      'p_offset': offset,
    }),
  );

  @override
  Future<MoneyCharge> charge(String id) async {
    final raw = await _rpc('admin_charge', {'p_charge_id': id});
    final row = raw is Map ? raw : const <String, dynamic>{};
    int n(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
    return MoneyCharge(
      id: '${row['id']}',
      groupId: '${row['group_id']}',
      venueName: '${row['venue_name'] ?? ''}',
      playerName: '${row['player_name'] ?? ''}',
      roomName: '${row['room_name'] ?? ''}',
      startsAt: DateTime.tryParse('${row['starts_at']}'),
      status: '${row['status'] ?? ''}',
      billingType: '${row['billing_type'] ?? ''}',
      amountCents: n(row['amount_cents']),
      chargedCents: n(row['charged_amount_cents']),
      interestCents: n(row['buyer_interest_cents']),
      discountCents: n(row['first_booking_discount_cents']),
      subsidyCents: n(row['subsidy_cents']),
      points: n(row['points_redeemed']),
      houseCents: n(row['house_fixed_cents']),
      divergence: '${row['split_divergence_event'] ?? ''}',
      custody: '${row['custody'] ?? ''}',
      attempts: n(row['custody_release_attempts']),
      groupClosed: row['group_closed'] == true,
      fullRefundCents: n(row['full_refund_cents']),
      queueStatus: '${row['refund_queue_status'] ?? ''}',
    );
  }

  MoneyMove _move(dynamic raw) {
    final row = raw is Map ? raw : const <String, dynamic>{};
    final amount = row['amount_cents'];
    return MoneyMove(
      groupId: '${row['group_id'] ?? ''}',
      amountCents: amount is int ? amount : int.tryParse('$amount'),
      groupReady: row['group_ready'] == true,
    );
  }

  @override
  Future<MoneyMove> refundCharge(
    String id,
    String confirm, {
    int? amountCents,
  }) async {
    return _move(
      await _rpc('admin_refund_charge', {
        'p_charge_id': id,
        'p_confirm': confirm,
        'p_amount_cents': amountCents,
      }),
    );
  }

  @override
  Future<MoneyMove> reopenCustody(String id, String confirm) async {
    return _move(
      await _rpc('admin_reopen_custody', {
        'p_charge_id': id,
        'p_confirm': confirm,
      }),
    );
  }

  @override
  Future<MoneyMove> reopenCac(String id, String confirm) async {
    return _move(
      await _rpc('admin_reopen_cac', {'p_charge_id': id, 'p_confirm': confirm}),
    );
  }

  @override
  Future<void> settle(String groupId) async {
    await _client.functions.invoke(
      'settle-charges',
      body: {'group_id': groupId},
    );
  }

  @override
  Future<CacFlag> cacFlag() async {
    final raw = await _rpc('admin_cac_transfers_flag', {});
    final row = raw is Map ? raw : const <String, dynamic>{};
    return CacFlag(
      readable: row['readable'] == true,
      enabled: row['enabled'] is bool ? row['enabled'] as bool : null,
    );
  }
}

class MemoryAdminMoneyApi implements AdminMoneyApi {
  MemoryAdminMoneyApi({List<Map<String, Object?>>? charges})
    : chargeRows = charges ?? const [];

  final List<Map<String, Object?>> chargeRows;
  final refundRows = <Map<String, Object?>>[];
  final settled = <String>[];
  bool custodyReset = false;
  bool cacReset = false;

  MoneyPage _filter(
    List<Map<String, Object?>> rows,
    String? query, {
    int offset = 0,
    int limit = 40,
  }) {
    final needle = (query ?? '').trim().toLowerCase();
    final kept = [
      for (final row in rows)
        if (needle.isEmpty ||
            '${row['venue_name']} ${row['player_name']}'.toLowerCase().contains(
              needle,
            ))
          row,
    ];
    return MoneyPage(
      total: kept.length,
      rows: kept.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<MoneyPage> charges({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _filter(chargeRows, query, offset: offset, limit: limit);

  @override
  Future<MoneyPage> refunds({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _filter(refundRows, query, offset: offset, limit: limit);

  @override
  Future<MoneyPage> withdrawals({
    String? query,
    String? status,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => const MoneyPage(total: 0, rows: []);

  @override
  Future<MoneyCharge> charge(String id) async {
    return MoneyCharge(
      id: id,
      groupId: 'grupo-caixa',
      venueName: 'Casa Dinheiro',
      playerName: 'Ana',
      roomName: 'Sala do Caixa',
      startsAt: DateTime.utc(2027, 12, 10, 21),
      status: 'paid',
      billingType: 'CREDIT_CARD',
      amountCents: 10000,
      chargedCents: 12000,
      interestCents: 2000,
      discountCents: 500,
      subsidyCents: 100,
      points: 100,
      houseCents: 8000,
      divergence: '',
      custody: custodyReset ? 'HELD' : 'falha',
      attempts: custodyReset ? 0 : 8,
      groupClosed: true,
      fullRefundCents: 12000,
      queueStatus: refundRows.isEmpty ? '' : 'queued',
    );
  }

  @override
  Future<MoneyMove> refundCharge(
    String id,
    String confirm, {
    int? amountCents,
  }) async {
    if (confirm != 'REEMBOLSAR') {
      throw const AdminRejected('confirmacao invalida');
    }
    if (amountCents != null && amountCents != 12000) {
      throw const AdminRejected('reembolso parcial sem fila');
    }
    refundRows.add({
      'id': 'fila-1',
      'player_name': 'Ana',
      'venue_name': 'Casa Dinheiro',
      'action': 'refund',
      'status': 'queued',
      'amount_cents': 12000,
    });
    return const MoneyMove(groupId: 'grupo-caixa', amountCents: 12000);
  }

  @override
  Future<MoneyMove> reopenCustody(String id, String confirm) async {
    if (confirm != 'LIBERAR') throw const AdminRejected('confirmacao invalida');
    custodyReset = true;
    return const MoneyMove(groupId: 'grupo-caixa', groupReady: true);
  }

  @override
  Future<MoneyMove> reopenCac(String id, String confirm) async {
    if (confirm != 'REPROCESSAR') {
      throw const AdminRejected('confirmacao invalida');
    }
    cacReset = true;
    return const MoneyMove(groupId: 'grupo-caixa');
  }

  @override
  Future<void> settle(String groupId) async {
    settled.add(groupId);
  }

  @override
  Future<CacFlag> cacFlag() async => const CacFlag(readable: false);
}

class MoneyDesk extends ConsumerStatefulWidget {
  const MoneyDesk({super.key});

  @override
  ConsumerState<MoneyDesk> createState() => _MoneyDeskState();
}

class _MoneyDeskState extends ConsumerState<MoneyDesk> {
  final _query = TextEditingController();
  final _partial = TextEditingController();
  MoneyPage? _charges;
  MoneyPage? _refunds;
  MoneyPage? _withdrawals;
  int _chargeOffset = 0;
  int _refundOffset = 0;
  MoneyCharge? _charge;
  CacFlag? _flag;
  String? _message;
  bool _includeTest = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _partial.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(adminMoneyProvider);
      final charges = await api.charges(
        query: _query.text,
        includeTest: _includeTest,
        offset: _chargeOffset,
      );
      final refunds = await api.refunds(
        includeTest: _includeTest,
        offset: _refundOffset,
      );
      final withdrawals = await api.withdrawals(
        query: _query.text,
        includeTest: _includeTest,
      );
      final flag = await api.cacFlag();
      if (!mounted) return;
      setState(() {
        _charges = charges;
        _refunds = refunds;
        _withdrawals = withdrawals;
        _flag = flag;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  Future<void> _open(String id) async {
    try {
      final detail = await ref.read(adminMoneyProvider).charge(id);
      if (!mounted) return;
      setState(() => _charge = detail);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  Future<void> _typed(
    String word,
    Future<MoneyMove> Function(String word) action,
  ) async {
    final ok = await confirmTyped(
      context,
      title: word,
      body: word == 'REEMBOLSAR'
          ? 'A fila existente devolve o valor integral da cobrança. Um valor diferente é recusado: não há estorno parcial.'
          : word == 'LIBERAR'
          ? 'Isto zera a tentativa. A PagBank só libera a custódia se o grupo já estiver confirmado ou fechado. O painel chama a função que já existe.'
          : 'Isto devolve o CAC que falhou para a fila. A transferência continua na função que já existe, e a flag não muda.',
      word: word,
    );
    if (!ok || !mounted) return;
    try {
      final move = await action(word);
      if (move.groupId.isNotEmpty) {
        await ref.read(adminMoneyProvider).settle(move.groupId);
      }
      if (!mounted) return;
      setState(() {
        _message = word == 'REEMBOLSAR'
            ? 'Estorno integral de ${reais(move.amountCents ?? 0)} na fila.'
            : word == 'LIBERAR'
            ? 'Tentativa zerada. ${move.groupReady ? 'O grupo já pode liberar.' : 'O grupo ainda não confirmou.'}'
            : 'CAC voltou para a fila.';
      });
      await _load();
      final current = _charge;
      if (current != null) await _open(current.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final charges = _charges;
    final charge = _charge;
    final flag = _flag;
    return Column(
      key: const Key('admin-dinheiro'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text('Custódia, estorno e CAC'),
        Text(
          flag == null
              ? 'Lendo a flag do CAC.'
              : flag.readable
              ? 'PAGBANK_CAC_TRANSFERS: ${flag.enabled == true ? 'ligada' : 'desligada'}'
              : 'PAGBANK_CAC_TRANSFERS fica só no ambiente da função. Este painel não lê segredo e não muda a flag.',
          key: const Key('admin-cac-flag'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('admin-dinheiro-busca'),
          controller: _query,
          decoration: const InputDecoration(
            labelText: 'Busca por casa ou jogador',
          ),
          onSubmitted: (_) {
            _chargeOffset = 0;
            _load();
          },
        ),
        FilterChip(
          label: const Text('Mostrar teste'),
          selected: _includeTest,
          onSelected: (value) {
            setState(() => _includeTest = value);
            _load();
          },
        ),
        if (_message != null)
          Text(_message!, key: const Key('admin-dinheiro-aviso')),
        if (charges == null)
          const Text('Carregando cobranças.')
        else if (charges.rows.isEmpty)
          const Text('Nenhuma cobrança neste recorte.')
        else
          for (final row in charges.rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${row['venue_name']} · ${row['player_name']}'),
              subtitle: Text(
                '${row['status']} · ${reais(_cents(row['amount_cents']))} · custódia ${row['custody']} · tentativa ${row['custody_release_attempts']}',
              ),
              onTap: () => _open('${row['id']}'),
            ),
        if (charges != null && charges.total > 40)
          Row(
            children: [
              Text('${charges.rows.length} de ${charges.total}'),
              TextButton(
                onPressed: _chargeOffset == 0
                    ? null
                    : () {
                        setState(() => _chargeOffset -= 40);
                        _load();
                      },
                child: const Text('Anterior'),
              ),
              TextButton(
                onPressed: _chargeOffset + charges.rows.length >= charges.total
                    ? null
                    : () {
                        setState(() => _chargeOffset += 40);
                        _load();
                      },
                child: const Text('Próxima'),
              ),
            ],
          ),
        if (charge != null) ...[
          const SizedBox(height: 8),
          Text(
            '${charge.playerName} · ${charge.roomName} · ${whenLabel(charge.startsAt)}',
            key: const Key('admin-cobranca'),
          ),
          Text(
            'Casa ${reais(charge.houseCents)} · juros ${reais(charge.interestCents)}',
          ),
          Text(
            '1ª sessão ${reais(charge.discountCents)} · pontos ${charge.points} · subsídio ${reais(charge.subsidyCents)}',
          ),
          Text(
            'Custódia ${charge.custody} · tentativas ${charge.attempts} · cobrado ${reais(charge.chargedCents)}',
          ),
          Text(
            charge.divergence.isEmpty
                ? 'Split sem divergência registrada.'
                : 'Divergência do split: ${charge.divergence}',
          ),
          const Text(
            'O número de parcelas não fica gravado na cobrança. A fila só estorna o valor integral.',
          ),
          TextField(
            key: const Key('admin-reembolso-valor'),
            controller: _partial,
            decoration: const InputDecoration(
              labelText: 'Centavos do estorno, vazio para o integral',
            ),
            keyboardType: TextInputType.number,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('admin-liberar-custodia'),
                onPressed: () => _typed(
                  'LIBERAR',
                  (word) => ref
                      .read(adminMoneyProvider)
                      .reopenCustody(charge.id, word),
                ),
                child: const Text('Liberar custódia'),
              ),
              TextButton(
                key: const Key('admin-reembolsar'),
                onPressed: () => _typed('REEMBOLSAR', (word) {
                  final typed = int.tryParse(_partial.text.trim());
                  return ref
                      .read(adminMoneyProvider)
                      .refundCharge(charge.id, word, amountCents: typed);
                }),
                child: const Text('Reembolsar'),
              ),
              TextButton(
                key: const Key('admin-reprocessar-cac'),
                onPressed: () => _typed(
                  'REPROCESSAR',
                  (word) =>
                      ref.read(adminMoneyProvider).reopenCac(charge.id, word),
                ),
                child: const Text('Reprocessar CAC'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const Text('Fila de reembolsos'),
        if (_refunds == null || _refunds!.rows.isEmpty)
          const Text('Fila vazia neste recorte.')
        else
          for (final row in _refunds!.rows)
            Text(
              '${row['player_name']} · ${row['action']} · ${row['status']} · ${reais(_cents(row['amount_cents']))}',
              key: const Key('admin-fila-reembolso'),
            ),
        if (_refunds != null && _refunds!.total > 40)
          TextButton(
            onPressed: _refundOffset + _refunds!.rows.length >= _refunds!.total
                ? null
                : () {
                    setState(() => _refundOffset += 40);
                    _load();
                  },
            child: const Text('Próxima da fila'),
          ),
        const SizedBox(height: 8),
        const Text('Saques'),
        if (_withdrawals == null || _withdrawals!.rows.isEmpty)
          const Text('Nenhum saque neste recorte.')
        else
          for (final row in _withdrawals!.rows)
            Text(
              '${row['venue_name']} · ${row['status']} · ${reais(_cents(row['amount_cents']))}',
            ),
      ],
    );
  }
}

int _cents(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
