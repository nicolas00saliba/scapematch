import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_confirm.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:scapematch_admin/admin_place.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final adminOpsProvider = Provider<AdminOpsApi>((ref) {
  if (!scapeUsesLiveBackend) {
    throw StateError('O Admin real ainda não ligou o Supabase.');
  }
  return SupabaseAdminOpsApi(scapeSupabase);
});

abstract class AdminOpsApi {
  Future<OpsPage> rooms({
    String? venueId,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<OpsPage> sessions({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<OpsPage> groups({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  });
  Future<OpsGroupDetail> group(String id);
  Future<OpsAction> deleteSession(String id, String confirm);
  Future<OpsAction> cancelGroup(String id, String confirm);
  Future<OpsAction> removeMember(String groupId, String memberId, String confirm);
}

class OpsPage {
  const OpsPage({required this.total, required this.rows});
  final int total;
  final List<Map<String, Object?>> rows;
}

class OpsAction {
  const OpsAction({required this.refundsQueued});
  final int refundsQueued;
}

class OpsGroupDetail {
  const OpsGroupDetail({
    required this.id,
    required this.venueName,
    required this.roomName,
    required this.sessionId,
    required this.startsAt,
    required this.status,
    required this.totalSpots,
    required this.filledSpots,
    required this.hostName,
    required this.members,
  });
  final String id;
  final String venueName;
  final String roomName;
  final String sessionId;
  final DateTime? startsAt;
  final String status;
  final int totalSpots;
  final int filledSpots;
  final String hostName;
  final List<OpsMember> members;
}

class OpsMember {
  const OpsMember({
    required this.id,
    required this.name,
    required this.host,
    required this.attendance,
    required this.paymentStatus,
    required this.refundStatus,
    required this.refundReason,
    required this.chargeStatus,
    required this.amountCents,
    required this.custody,
  });
  final String id;
  final String name;
  final bool host;
  final String attendance;
  final String paymentStatus;
  final String refundStatus;
  final String refundReason;
  final String chargeStatus;
  final int amountCents;
  final String custody;
}

class SupabaseAdminOpsApi implements AdminOpsApi {
  SupabaseAdminOpsApi(this._client);
  final SupabaseClient _client;

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) {
    return _client.rpc(name, params: params);
  }

  Map<String, dynamic> _filters({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    required bool includeTest,
    required int limit,
    required int offset,
    bool dated = false,
  }) {
    return {
      'p_venue_id': venueId,
      if (dated) 'p_from': from?.toUtc().toIso8601String(),
      if (dated) 'p_to': to?.toUtc().toIso8601String(),
      if (dated) 'p_status': status,
      'p_query': query,
      'p_include_test': includeTest,
      'p_limit': limit,
      'p_offset': offset,
    };
  }

  OpsPage _page(dynamic raw) {
    final row = raw is Map ? raw : const <String, dynamic>{};
    final rows = row['rows'];
    return OpsPage(
      total: row['total'] is int ? row['total'] as int : int.tryParse('${row['total']}') ?? 0,
      rows: [
        for (final item in rows is List ? rows : const [])
          if (item is Map) Map<String, Object?>.from(item),
      ],
    );
  }

  @override
  Future<OpsPage> rooms({
    String? venueId,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async {
    return _page(await _rpc('admin_list_rooms', _filters(
      venueId: venueId,
      query: query,
      includeTest: includeTest,
      limit: limit,
      offset: offset,
    )));
  }

  @override
  Future<OpsPage> sessions({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async {
    return _page(await _rpc('admin_list_sessions', _filters(
      venueId: venueId,
      from: from,
      to: to,
      status: status,
      query: query,
      includeTest: includeTest,
      limit: limit,
      offset: offset,
      dated: true,
    )));
  }

  @override
  Future<OpsPage> groups({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async {
    return _page(await _rpc('admin_list_groups', _filters(
      venueId: venueId,
      from: from,
      to: to,
      status: status,
      query: query,
      includeTest: includeTest,
      limit: limit,
      offset: offset,
      dated: true,
    )));
  }

  @override
  Future<OpsGroupDetail> group(String id) async {
    final raw = await _rpc('admin_group', {'p_group_id': id});
    final row = raw is Map ? raw : const <String, dynamic>{};
    final members = row['members'];
    return OpsGroupDetail(
      id: '${row['id'] ?? id}',
      venueName: '${row['venue_name'] ?? ''}',
      roomName: '${row['room_name'] ?? ''}',
      sessionId: '${row['session_id'] ?? ''}',
      startsAt: DateTime.tryParse('${row['starts_at'] ?? ''}'),
      status: '${row['status'] ?? ''}',
      totalSpots: int.tryParse('${row['total_spots']}') ?? 0,
      filledSpots: int.tryParse('${row['filled_spots']}') ?? 0,
      hostName: '${row['host_name'] ?? ''}',
      members: [
        for (final item in members is List ? members : const [])
          if (item is Map)
            OpsMember(
              id: '${item['id'] ?? ''}',
              name: '${item['display_name'] ?? ''}',
              host: item['is_creator'] == true,
              attendance: '${item['attendance'] ?? ''}',
              paymentStatus: '${item['payment_status'] ?? ''}',
              refundStatus: '${item['refund_status'] ?? ''}',
              refundReason: '${item['refund_reason'] ?? ''}',
              chargeStatus: '${item['charge_status'] ?? ''}',
              amountCents: int.tryParse('${item['amount_cents']}') ?? 0,
              custody: '${item['custody'] ?? ''}',
            ),
      ],
    );
  }

  @override
  Future<OpsAction> deleteSession(String id, String confirm) async {
    final raw = await _rpc('admin_delete_session', {
      'p_session_id': id,
      'p_confirm': confirm,
    });
    return _action(raw);
  }

  @override
  Future<OpsAction> cancelGroup(String id, String confirm) async {
    final raw = await _rpc('admin_cancel_group', {
      'p_group_id': id,
      'p_confirm': confirm,
    });
    return _action(raw);
  }

  @override
  Future<OpsAction> removeMember(
    String groupId,
    String memberId,
    String confirm,
  ) async {
    final raw = await _rpc('admin_remove_group_member', {
      'p_group_id': groupId,
      'p_member_id': memberId,
      'p_confirm': confirm,
    });
    final row = raw is Map ? raw : const <String, dynamic>{};
    final queued = row['refund_queued'] == true ? 1 : 0;
    return OpsAction(refundsQueued: queued);
  }

  OpsAction _action(dynamic raw) {
    final row = raw is Map ? raw : const <String, dynamic>{};
    return OpsAction(
      refundsQueued: int.tryParse('${row['refunds_queued']}') ?? 0,
    );
  }
}

class MemoryAdminOpsApi implements AdminOpsApi {
  MemoryAdminOpsApi()
    : roomsRows = [
        {
          'id': 'sala-cofre',
          'venue_id': 'casa-ninja',
          'venue_name': 'Ninja Escape',
          'name': 'O Cofre',
        },
      ],
      sessionsRows = [
        {
          'id': 'sessao-cofre',
          'venue_name': 'Ninja Escape',
          'room_name': 'O Cofre',
          'starts_at': '2027-12-01T21:00:00Z',
          'cancelled': false,
          'paid_members': 1,
        },
      ],
      groupsRows = [
        {
          'id': 'grupo-cofre',
          'venue_id': 'casa-ninja',
          'venue_name': 'Ninja Escape',
          'room_name': 'O Cofre',
          'session_id': 'sessao-cofre',
          'starts_at': '2027-12-01T21:00:00Z',
          'status': 'open',
          'filled_spots': 2,
          'total_spots': 6,
          'host_name': 'Nícolas',
        },
      ];

  final List<Map<String, Object?>> roomsRows;
  final List<Map<String, Object?>> sessionsRows;
  final List<Map<String, Object?>> groupsRows;
  int refunds = 0;
  bool sessionCancelled = false;
  bool groupCancelled = false;
  final removed = <String>{};

  OpsPage _filter(List<Map<String, Object?>> rows, String? venueId, String? query) {
    final needle = (query ?? '').trim().toLowerCase();
    final kept = [
      for (final row in rows)
        if (venueId == null || venueId.isEmpty || row['venue_id'] == venueId)
          if (needle.isEmpty ||
              '${row['name'] ?? ''} ${row['venue_name'] ?? ''} ${row['room_name'] ?? ''}'
                  .toLowerCase()
                  .contains(needle))
            row,
    ];
    return OpsPage(total: kept.length, rows: kept);
  }

  @override
  Future<OpsPage> rooms({
    String? venueId,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _filter(roomsRows, venueId, query);

  @override
  Future<OpsPage> sessions({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _filter(sessionsRows, venueId, query);

  @override
  Future<OpsPage> groups({
    String? venueId,
    DateTime? from,
    DateTime? to,
    String? status,
    String? query,
    bool includeTest = false,
    int limit = 40,
    int offset = 0,
  }) async => _filter(groupsRows, venueId, query);

  @override
  Future<OpsGroupDetail> group(String id) async {
    return OpsGroupDetail(
      id: id,
      venueName: 'Ninja Escape',
      roomName: 'O Cofre',
      sessionId: 'sessao-cofre',
      startsAt: DateTime.utc(2027, 12, 1, 21),
      status: groupCancelled ? 'cancelled' : 'open',
      totalSpots: 6,
      filledSpots: groupCancelled ? 0 : 2,
      hostName: 'Nícolas',
      members: [
        OpsMember(
          id: 'membro-host',
          name: 'Nícolas',
          host: true,
          attendance: groupCancelled ? 'cancelled' : 'joined',
          paymentStatus: 'paid',
          refundStatus: 'none',
          refundReason: 'none',
          chargeStatus: 'paid',
          amountCents: 12000,
          custody: 'HELD',
        ),
        OpsMember(
          id: 'membro-ana',
          name: 'Ana',
          host: false,
          attendance: groupCancelled || removed.contains('membro-ana')
              ? 'cancelled'
              : 'joined',
          paymentStatus: 'paid',
          refundStatus: removed.contains('membro-ana') ? 'refund_pending' : 'none',
          refundReason: removed.contains('membro-ana')
              ? 'organizer_removed_member'
              : 'none',
          chargeStatus: 'paid',
          amountCents: 12000,
          custody: 'HELD',
        ),
      ],
    );
  }

  @override
  Future<OpsAction> deleteSession(String id, String confirm) async {
    if (confirm != 'EXCLUIR') throw const AdminRejected('confirmacao invalida');
    sessionCancelled = true;
    groupCancelled = true;
    refunds = 2;
    for (final row in groupsRows) {
      if (row['session_id'] == id) row['status'] = 'cancelled';
    }
    for (final row in sessionsRows) {
      if (row['id'] == id) row['cancelled'] = true;
    }
    return const OpsAction(refundsQueued: 2);
  }

  @override
  Future<OpsAction> cancelGroup(String id, String confirm) async {
    if (confirm != 'CANCELAR') throw const AdminRejected('confirmacao invalida');
    groupCancelled = true;
    refunds = 2;
    return const OpsAction(refundsQueued: 2);
  }

  @override
  Future<OpsAction> removeMember(
    String groupId,
    String memberId,
    String confirm,
  ) async {
    if (confirm != 'REMOVER') throw const AdminRejected('confirmacao invalida');
    removed.add(memberId);
    return const OpsAction(refundsQueued: 1);
  }
}

String _statusLabel(String status) => switch (status) {
  'open' => 'aberto',
  'closed' => 'fechado',
  'cancelled' => 'cancelado',
  _ => status,
};

String _payLabel(String status) => switch (status) {
  'paid' => 'pago',
  'pending' => 'pendente',
  'authorized' => 'autorizado',
  'refunded' => 'estornado',
  'none' => 'nenhum',
  'refund_pending' => 'estorno na fila',
  'released' => 'liberado',
  'reserved' => 'reservado',
  _ => status,
};

class OperacaoPage extends ConsumerStatefulWidget {
  const OperacaoPage({super.key});

  @override
  ConsumerState<OperacaoPage> createState() => _OperacaoPageState();
}

class _OperacaoPageState extends ConsumerState<OperacaoPage> {
  final _query = TextEditingController();
  String _tab = 'grupos';
  String? _venueId;
  String? _status;
  bool _includeTest = false;
  int _offset = 0;
  OpsPage? _page;
  OpsGroupDetail? _group;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final place = ref.read(adminPlaceProvider);
    if (place.section == AdminSection.operacao && place.id != null) {
      _venueId = place.id;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(adminOpsProvider);
      final page = switch (_tab) {
        'salas' => await api.rooms(
          venueId: _venueId,
          query: _query.text,
          includeTest: _includeTest,
          offset: _offset,
        ),
        'sessoes' => await api.sessions(
          venueId: _venueId,
          status: _status,
          query: _query.text,
          includeTest: _includeTest,
          offset: _offset,
        ),
        _ => await api.groups(
          venueId: _venueId,
          status: _status,
          query: _query.text,
          includeTest: _includeTest,
          offset: _offset,
        ),
      };
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
        _message = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = adminErrorText(error);
      });
    }
  }

  Future<void> _openGroup(String id) async {
    try {
      final detail = await ref.read(adminOpsProvider).group(id);
      if (!mounted) return;
      setState(() => _group = detail);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  Future<void> _typed(String word, Future<OpsAction> Function(String word) action) async {
    final ok = await confirmTyped(
      context,
      title: word,
      body: word == 'EXCLUIR'
          ? 'Se já houver jogador pago, o estorno integral de todos entra na fila, motivo sessão cancelada pelo organizador.'
          : word == 'CANCELAR'
          ? 'O grupo sai da grade. Quem tem cobrança viva recebe estorno integral na fila. A sessão continua.'
          : 'Este membro sai e, se tiver cobrança viva, o estorno entra na fila.',
      word: word,
    );
    if (!ok || !mounted) return;
    try {
      final result = await action(word);
      if (!mounted) return;
      await _load();
      final group = _group;
      if (group != null && mounted) await _openGroup(group.id);
      if (!mounted) return;
      setState(() {
        _message = result.refundsQueued == 0
            ? 'Feito. Nenhuma cobrança viva entrou na fila.'
            : 'Feito. ${result.refundsQueued} reembolso(s) na fila.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final group = _group;
    return AdminFrame(
      key: const Key('admin-operacao'),
      title: 'Operação',
      leading: _venueId == null
          ? null
          : IconButton(
              tooltip: 'Voltar à casa',
              onPressed: () => ref
                  .read(adminPlaceProvider.notifier)
                  .openSection(AdminSection.casas, _venueId!),
              icon: const Icon(Icons.arrow_back),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final item in const [
                ('grupos', 'Grupos'),
                ('sessoes', 'Sessões'),
                ('salas', 'Salas'),
              ])
                ChoiceChip(
                  key: Key('admin-operacao-${item.$1}'),
                  label: Text(item.$2),
                  selected: _tab == item.$1,
                  onSelected: (_) {
                    setState(() {
                      _tab = item.$1;
                      _offset = 0;
                      _group = null;
                    });
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
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('admin-operacao-busca'),
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Busca por casa ou sala',
            ),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          if (_tab != 'salas') ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final item in _tab == 'sessoes'
                    ? const [('open', 'Abertas'), ('cancelled', 'Canceladas')]
                    : const [
                        ('open', 'Abertos'),
                        ('closed', 'Fechados'),
                        ('cancelled', 'Cancelados'),
                      ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: _status == item.$1,
                    onSelected: (selected) {
                      setState(() => _status = selected ? item.$1 : null);
                      _load();
                    },
                  ),
              ],
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, key: const Key('admin-operacao-aviso')),
          ],
          const SizedBox(height: 12),
          if (_loading || page == null)
            Text(_message ?? 'Carregando…')
          else if (page.rows.isEmpty)
            const Text('Nada neste recorte.')
          else
            for (final row in page.rows) _line(row),
          if (page != null && page.total > page.rows.length)
            TextButton(
              onPressed: () {
                setState(() => _offset += 40);
                _load();
              },
              child: Text('Mais (${page.total - _offset - page.rows.length} restantes)'),
            ),
          if (group != null) ...[
            const SizedBox(height: 16),
            Text(
              '${group.venueName} · ${group.roomName} · ${whenLabel(group.startsAt)}',
              key: const Key('admin-grupo'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Host ${group.hostName} · ${group.filledSpots} de ${group.totalSpots} vagas · ${_statusLabel(group.status)}',
            ),
            if (group.sessionId.isNotEmpty && group.status != 'cancelled')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('admin-excluir-sessao'),
                  onPressed: () => _typed(
                    'EXCLUIR',
                    (word) => ref
                        .read(adminOpsProvider)
                        .deleteSession(group.sessionId, word),
                  ),
                  child: const Text('Excluir sessão'),
                ),
              ),
            if (group.status != 'cancelled')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('admin-cancelar-grupo'),
                  onPressed: () => _typed(
                    'CANCELAR',
                    (word) => ref.read(adminOpsProvider).cancelGroup(group.id, word),
                  ),
                  child: const Text('Cancelar grupo'),
                ),
              ),
            for (final member in group.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${member.name}${member.host ? ' · host' : ''} · ${_payLabel(member.paymentStatus)}',
                ),
                subtitle: Text(
                  member.chargeStatus.isEmpty
                      ? 'Sem cobrança'
                      : '${_payLabel(member.chargeStatus)} · ${reais(member.amountCents)} · custódia ${member.custody} · estorno ${_payLabel(member.refundStatus)}',
                ),
                trailing: member.attendance == 'cancelled'
                    ? null
                    : TextButton(
                        key: Key('admin-remover-${member.id}'),
                        onPressed: () => _typed(
                          'REMOVER',
                          (word) => ref.read(adminOpsProvider).removeMember(
                            group.id,
                            member.id,
                            word,
                          ),
                        ),
                        child: const Text('Remover'),
                      ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _line(Map<String, Object?> row) {
    final title = switch (_tab) {
      'salas' => '${row['venue_name']} · ${row['name']}',
      'sessoes' =>
        '${row['venue_name']} · ${row['room_name']} · ${whenLabel(DateTime.tryParse('${row['starts_at']}'))}',
      _ =>
        '${row['venue_name']} · ${row['room_name']} · ${whenLabel(DateTime.tryParse('${row['starts_at']}'))} · ${row['host_name']}',
    };
    final id = '${row['id']}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(
        _tab == 'grupos'
            ? '${row['filled_spots']} de ${row['total_spots']} · ${_statusLabel('${row['status']}')}'
            : _tab == 'sessoes'
            ? '${row['cancelled'] == true ? 'cancelada' : 'aberta'} · pagos ${row['paid_members']}'
            : 'Sala',
      ),
      onTap: _tab == 'grupos' ? () => _openGroup(id) : null,
    );
  }
}
