import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_place.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_theme.dart';

class CasasPage extends ConsumerStatefulWidget {
  const CasasPage({super.key});

  @override
  ConsumerState<CasasPage> createState() => _CasasPageState();
}

class _CasasPageState extends ConsumerState<CasasPage> {
  String _status = '';
  final _query = TextEditingController();
  VenueBoard? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final board = await ref.read(adminApiProvider).venues(
        status: _status.isEmpty ? null : _status,
        query: _query.text,
      );
      if (!mounted) return;
      setState(() {
        _board = board;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFrame(
      title: 'Casas',
      key: const Key('admin-casas'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in const [
                ('', 'Todas'),
                ('pending', 'Pendentes'),
                ('approved', 'Aprovadas'),
                ('suspended', 'Suspensas'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _status == item.$1,
                  onSelected: (_) {
                    setState(() => _status = item.$1);
                    _load();
                  },
                ),
              SizedBox(
                width: 240,
                child: TextField(
                  key: const Key('admin-casas-busca'),
                  controller: _query,
                  decoration: const InputDecoration(labelText: 'Buscar casa'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              if (_board != null)
                Text('Oficial agora: ${percentBps(_board!.platformBps)}'),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!),
          if (_board == null && _error == null) const Text('Carregando casas…'),
          if (_board != null)
            for (final house in _board!.houses)
              Card(
                child: ListTile(
                  title: Text(house.name),
                  subtitle: Text(
                    '${_statusLabel(house)} · ${percentBps(house.commissionBps)}'
                    '${house.commissionOverride ? ' (desta casa)' : ' (oficial)'}'
                    '${house.hasWallet ? '' : ' · sem subconta'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ref.read(adminPlaceProvider.notifier).open(house.id),
                ),
              ),
        ],
      ),
    );
  }
}

class CasaPage extends ConsumerStatefulWidget {
  const CasaPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<CasaPage> createState() => _CasaPageState();
}

class _CasaPageState extends ConsumerState<CasaPage> {
  VenueProfile? _house;
  String? _message;
  final _neighborhood = TextEditingController();
  final _bps = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _neighborhood.dispose();
    _bps.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final house = await ref.read(adminApiProvider).venue(widget.id);
    if (!mounted) return;
    _neighborhood.text = house.neighborhood;
    _bps.text = house.commissionBps.toString();
    setState(() => _house = house);
  }

  @override
  Widget build(BuildContext context) {
    final house = _house;
    return AdminFrame(
      key: const Key('admin-casa'),
      title: house?.name ?? 'Casa',
      leading: IconButton(
        tooltip: 'Voltar',
        onPressed: () => ref.read(adminPlaceProvider.notifier).close(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: house == null
          ? const Text('Carregando casa…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_statusLabelRow(house)} · ${house.cityId} · ${house.ownerName} · ${house.ownerEmail}',
                ),
                Text(
                  '${house.documentKind.toUpperCase()} final ${house.documentLast4} · ${house.phone}',
                ),
                if (house.suggestNinja)
                  const Text('Esta casa pede a comissão Ninja, 20%.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (house.status == 'pending') ...[
                      FilledButton(
                        key: const Key('admin-aprovar'),
                        onPressed: () => _review('approved'),
                        child: const Text('Aprovar'),
                      ),
                      OutlinedButton(
                        onPressed: () => _review('rejected'),
                        child: const Text('Reprovar'),
                      ),
                    ],
                    if (house.status == 'approved')
                      OutlinedButton(
                        onPressed: () async {
                          await ref.read(adminApiProvider).suspendVenue(
                            house.id,
                            !house.suspended,
                          );
                          await _load();
                        },
                        child: Text(house.suspended ? 'Reativar' : 'Suspender'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _neighborhood,
                  decoration: const InputDecoration(labelText: 'Bairro'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () async {
                      final next = await ref.read(adminApiProvider).updateVenue(
                        house.id,
                        {'neighborhood': _neighborhood.text.trim()},
                      );
                      setState(() => _house = next);
                    },
                    child: const Text('Salvar dados'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Comissão desta casa. A oficial é 25% e a Ninja é 20%. A cobrança já feita guarda o percentual dela.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _commission(2500),
                      child: const Text('25% oficial'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _commission(2000),
                      child: const Text('20% Ninja'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('admin-comissao'),
                  controller: _bps,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Pontos-base (2500 = 25%)',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () => _commission(int.tryParse(_bps.text) ?? 0),
                    child: const Text('Gravar comissão'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Snapshots das reservas'),
                for (final snap in house.snapshots)
                  Text(
                    '${snap.status} · ${percentBps(snap.commissionBps)} · ${snap.id}',
                  ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, key: const Key('admin-casa-aviso')),
                ],
              ],
            ),
    );
  }

  Future<void> _commission(int bps) async {
    await ref.read(adminApiProvider).setCommission(venueId: widget.id, bps: bps);
    await _load();
    setState(() => _message = 'Comissão gravada em ${percentBps(bps)}. As reservas antigas não mudam.');
  }

  Future<void> _review(String decision) async {
    final api = ref.read(adminApiProvider);
    final result = await api.reviewVenue(widget.id, decision);
    String? wallet;
    if (result.needsSubaccount) {
      wallet = await api.provisionWallet(widget.id);
    }
    await _load();
    setState(() {
      _message = result.needsSubaccount
          ? (wallet ?? 'Aprovada. A subconta Asaas foi pedida no fluxo que já existe.')
          : 'Decisão gravada: ${result.status}.';
    });
  }
}

class JogadoresPage extends ConsumerStatefulWidget {
  const JogadoresPage({super.key});

  @override
  ConsumerState<JogadoresPage> createState() => _JogadoresPageState();
}

class _JogadoresPageState extends ConsumerState<JogadoresPage> {
  final _query = TextEditingController();
  List<PlayerRow> _players = const [];
  List<ReviewRow> _queue = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(adminApiProvider);
    try {
      final players = await api.players(_query.text);
      final queue = await api.referralQueue();
      if (!mounted) return;
      setState(() {
        _players = players;
        _queue = queue;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFrame(
      key: const Key('admin-jogadores'),
      title: 'Jogadores',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Contas indicadas em revisão', style: Theme.of(context).textTheme.titleMedium),
          if (_queue.isEmpty) const Text('Nenhuma conta em revisão.'),
          for (final row in _queue)
            Card(
              child: ListTile(
                title: Text(row.label),
                subtitle: Text(
                  '${row.entryCount} lançamentos · ${reais(row.amountCents)}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      key: const Key('admin-revisao-aprovar'),
                      onPressed: () => _decide(row, 'approve'),
                      child: const Text('Aprovar'),
                    ),
                    OutlinedButton(
                      onPressed: () => _decide(row, 'reject'),
                      child: const Text('Rejeitar'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('admin-jogadores-busca'),
            controller: _query,
            decoration: const InputDecoration(labelText: 'Nome, e-mail ou usuário'),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!),
          for (final player in _players)
            Card(
              child: ListTile(
                title: Text(player.name),
                subtitle: Text(
                  '${player.email}${player.suspended ? ' · suspenso' : ''}',
                ),
                onTap: () => ref.read(adminPlaceProvider.notifier).open(player.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _decide(ReviewRow row, String decision) async {
    await ref.read(adminApiProvider).decideReferral(
      userId: row.userId,
      venueId: row.venueId,
      decision: decision,
    );
    await _load();
  }
}

class JogadorPage extends ConsumerStatefulWidget {
  const JogadorPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<JogadorPage> createState() => _JogadorPageState();
}

class _JogadorPageState extends ConsumerState<JogadorPage> {
  PlayerProfile? _player;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final player = await ref.read(adminApiProvider).player(widget.id);
    if (!mounted) return;
    setState(() => _player = player);
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return AdminFrame(
      key: const Key('admin-jogador'),
      title: player?.name ?? 'Jogador',
      leading: IconButton(
        onPressed: () => ref.read(adminPlaceProvider.notifier).close(),
        icon: const Icon(Icons.arrow_back),
      ),
      child: player == null
          ? const Text('Carregando jogador…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${player.email} · @${player.username}'),
                Text(
                  'Nível ${player.tier} · bônus ${percentBps(player.tierBonusBps)} · ${player.activeReferrals} indicações ativas',
                ),
                Text('Código ${player.referralCode.isEmpty ? '—' : player.referralCode}'),
                Text(
                  'Saldo ${player.availablePoints} pontos (${reais(player.availablePoints * player.pointValueCents)}) · ${player.pendingPoints} a liberar',
                ),
                if (player.referredBy.isNotEmpty)
                  Text('Entrou pelo código ${player.referredBy}'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(adminApiProvider).suspendPlayer(
                      player.id,
                      !player.suspended,
                    );
                    await _load();
                  },
                  child: Text(player.suspended ? 'Reativar conta' : 'Suspender conta'),
                ),
                const SizedBox(height: 16),
                const Text('Reservas'),
                for (final line in player.reservations) Text(line),
                const SizedBox(height: 12),
                const Text('Extrato de Scape Points'),
                for (final line in player.entries) Text(line),
                const SizedBox(height: 12),
                const Text('Indicações feitas'),
                for (final line in player.referralsMade) Text(line),
              ],
            ),
    );
  }
}

class RegrasPage extends ConsumerStatefulWidget {
  const RegrasPage({super.key});

  @override
  ConsumerState<RegrasPage> createState() => _RegrasPageState();
}

class _RegrasPageState extends ConsumerState<RegrasPage> {
  Map<String, Object?>? _settings;
  List<Map<String, Object?>> _history = const [];
  final _fields = <String, TextEditingController>{};
  bool _blockSelf = true;
  String? _message;

  static const _numbers = <(String, String)>[
    ('c2c_bps', 'Indicação jogador → jogador (pontos-base)'),
    ('b2c_bps', 'Casa → jogador (pontos-base)'),
    ('c2b_bps', 'Jogador → casa (pontos-base)'),
    ('b2b_bps', 'Casa → casa (pontos-base)'),
    ('cashback_bps', 'Cashback do pagador (pontos-base)'),
    ('redeem_min_points', 'Mínimo de pontos para resgatar'),
    ('redeem_max_bps', 'Teto do resgate (3000 = 30%)'),
    ('welcome_points', 'Boas-vindas (pontos)'),
    ('empty_slot_house_share_bps', 'Parte da casa no horário vazio'),
    ('tier_silver_active', 'Indicações ativas para prata'),
    ('tier_silver_bonus_bps', 'Bônus da prata'),
    ('tier_gold_active', 'Indicações ativas para ouro'),
    ('tier_gold_bonus_bps', 'Bônus do ouro'),
    ('tier_active_days', 'Janela do nível, em dias'),
    ('payer_referred_account_cap', 'Contas que um pagador pode premiar'),
    ('same_device_review_threshold', 'Mesmo aparelho manda para revisão'),
    ('point_value_cents', 'Centavos de cada ponto'),
    ('hold_days', 'Dias de carência'),
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _numbers) {
      _fields[field.$1] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(adminApiProvider);
    final settings = await api.rewardSettings();
    final history = await api.rewardHistory();
    if (!mounted) return;
    for (final field in _numbers) {
      _fields[field.$1]!.text = '${settings[field.$1] ?? ''}';
    }
    setState(() {
      _settings = settings;
      _history = history;
      _blockSelf = settings['block_self_payer'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminFrame(
      key: const Key('admin-regras'),
      title: 'Comissões e recompensas',
      child: _settings == null
          ? const Text('Carregando regras…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Estas regras já estão em referral_program_settings. Cada gravação fica no histórico.',
                ),
                const SizedBox(height: 12),
                for (final field in _numbers) ...[
                  TextField(
                    controller: _fields[field.$1],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: field.$2),
                  ),
                  const SizedBox(height: 8),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Travar quando o pagador é o próprio indicador'),
                  value: _blockSelf,
                  onChanged: (value) => setState(() => _blockSelf = value),
                ),
                FilledButton(
                  key: const Key('admin-salvar-regras'),
                  onPressed: _save,
                  child: const Text('Salvar regras'),
                ),
                if (_message != null) Text(_message!),
                const SizedBox(height: 16),
                Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
                if (_history.isEmpty) const Text('Nenhuma alteração ainda.'),
                for (final row in _history.take(8))
                  Text('${row['created_at'] ?? 'agora'} · alteração registrada'),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final patch = <String, Object?>{
      for (final field in _numbers)
        field.$1: int.tryParse(_fields[field.$1]!.text.trim()) ?? 0,
      'block_self_payer': _blockSelf,
    };
    await ref.read(adminApiProvider).saveRewardSettings(patch);
    await _load();
    setState(() => _message = 'Regras gravadas.');
  }
}

class GanhosPage extends ConsumerStatefulWidget {
  const GanhosPage({super.key});

  @override
  ConsumerState<GanhosPage> createState() => _GanhosPageState();
}

class _GanhosPageState extends ConsumerState<GanhosPage> {
  EarningsReport? _report;
  String _period = 'tudo';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now().toUtc();
    DateTime? from;
    if (_period == '30') from = now.subtract(const Duration(days: 30));
    if (_period == 'mes') from = DateTime.utc(now.year, now.month);
    final report = await ref.read(adminApiProvider).earnings(from: from);
    if (!mounted) return;
    setState(() => _report = report);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AdminFrame(
      key: const Key('admin-ganhos'),
      title: 'Ganhos',
      child: report == null
          ? const Text('Carregando ganhos…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      ('tudo', 'Tudo'),
                      ('30', '30 dias'),
                      ('mes', 'Este mês'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: _period == item.$1,
                        onSelected: (_) {
                          setState(() => _period = item.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    MetricCard(
                      label: 'Comissão bruta',
                      value: reais(report.grossCommissionCents),
                    ),
                    MetricCard(
                      label: 'Recompensas resgatadas',
                      value: reais(report.rewardsRedeemedCents),
                    ),
                    MetricCard(
                      label: 'Cashback emitido',
                      value: reais(report.cashbackIssuedCents),
                    ),
                    MetricCard(
                      label: 'Pontos em aberto',
                      value:
                          '${report.openPoints} · ${reais(report.openPointsCents)}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (report.asaasFeeCents == null)
                  const Text(
                    'A taxa do Asaas ainda não chegou neste recorte. O painel não estima esse valor.',
                    key: Key('admin-taxa-ausente'),
                  )
                else
                  Text(
                    'Taxa do Asaas, paga pela comissão do ScapeMatch: ${reais(report.asaasFeeCents!)} em ${report.asaasFeeRows} cobranças.',
                    key: const Key('admin-taxa-asaas'),
                  ),
                const SizedBox(height: 16),
                Text('Por casa', style: Theme.of(context).textTheme.titleMedium),
                for (final house in report.byVenue)
                  Text(
                    '${house.name}: comissão ${reais(house.grossCommissionCents)} · resgates ${reais(house.rewardsRedeemedCents)} · dívida ${reais(house.openDebtCents)}',
                  ),
                const SizedBox(height: 16),
                Text(
                  'Dívidas e créditos ainda abertos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (report.openComponents.isEmpty)
                  const Text('Nenhum componente em aberto.'),
                for (final item in report.openComponents)
                  Text(
                    '${item.venueName} · ${_componentLabel(item)} · ${reais(item.openCents)}'
                    '${item.allOrNothing ? ' · tudo ou nada' : ''}',
                  ),
              ],
            ),
    );
  }
}

class DestaquesPage extends ConsumerStatefulWidget {
  const DestaquesPage({super.key});

  @override
  ConsumerState<DestaquesPage> createState() => _DestaquesPageState();
}

class _DestaquesPageState extends ConsumerState<DestaquesPage> {
  HighlightsBoard? _board;
  final _ranks = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _ranks.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final board = await ref.read(adminApiProvider).highlights();
    if (!mounted) return;
    setState(() => _board = board);
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return AdminFrame(
      key: const Key('admin-destaques'),
      title: 'Destaques',
      child: board == null
          ? const Text('Carregando destaques…')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O número menor aparece antes na home do jogador. Vazio tira o item da seleção.',
                ),
                _block('Casas', 'venue', board.venues),
                _block('Salas', 'room', board.rooms),
                _block('Carrossel de novidades', 'news', board.news),
              ],
            ),
    );
  }

  Widget _block(String title, String kind, List<NamedRank> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text(item.subtitle),
            trailing: SizedBox(
              width: 160,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller(item),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Ordem'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Gravar',
                    onPressed: () => _save(kind, item.id),
                    icon: const Icon(Icons.check, color: adminTeal),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  TextEditingController _controller(NamedRank item) {
    return _ranks.putIfAbsent(
      item.id,
      () => TextEditingController(text: item.rank?.toString() ?? ''),
    );
  }

  Future<void> _save(String kind, String id) async {
    final raw = _ranks[id]?.text.trim() ?? '';
    await ref.read(adminApiProvider).setHighlight(
      kind,
      id,
      raw.isEmpty ? null : int.tryParse(raw),
    );
    await _load();
  }
}

class AuditoriaPage extends ConsumerStatefulWidget {
  const AuditoriaPage({super.key});

  @override
  ConsumerState<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends ConsumerState<AuditoriaPage> {
  List<AuditRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(adminApiProvider).audit();
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    return AdminFrame(
      key: const Key('admin-auditoria'),
      title: 'Auditoria',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Quem fez, quando, e o antes e o depois.'),
          const SizedBox(height: 12),
          if (_rows.isEmpty) const Text('Nenhuma ação ainda.'),
          for (final row in _rows)
            Card(
              child: ListTile(
                title: Text('${row.action} · ${row.targetTable}'),
                subtitle: Text(
                  '${whenLabel(row.createdAt)} · ${row.targetId}\nantes ${row.before}\ndepois ${row.after}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminFrame extends StatelessWidget {
  const AdminFrame({
    super.key,
    required this.title,
    required this.child,
    this.leading,
  });

  final String title;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (leading != null || wide)
              Row(
                children: [
                  ?leading,
                  if (wide)
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: adminTeal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            if (leading != null || wide) const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(VenueRow house) {
  if (house.suspended) return 'suspensa';
  return _statusWord(house.status);
}

String _statusLabelRow(VenueProfile house) {
  if (house.suspended) return 'suspensa';
  return _statusWord(house.status);
}

String _statusWord(String status) {
  return switch (status) {
    'pending' => 'pendente',
    'approved' => 'aprovada',
    'rejected' => 'reprovada',
    'merged' => 'unida a outra',
    _ => status,
  };
}

String _componentLabel(OpenComponent item) {
  return switch (item.kind) {
    'clawback' => 'dívida tudo ou nada',
    'cashback_debit' => 'débito de cashback',
    'venue_credit' => 'crédito da casa',
    _ => item.kind,
  };
}
