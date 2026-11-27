import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_confirm.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_notice.dart';
import 'package:scapematch_admin/admin_people.dart';
import 'package:scapematch_admin/admin_place.dart';
import 'package:scapematch_admin/admin_reward_fields.dart';
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
  List<VenueClaimRow> _claims = const [];
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
      final api = ref.read(adminApiProvider);
      final board = await api.venues(
        status: _status.isEmpty ? null : _status,
        query: _query.text,
      );
      final claims = await api.venueClaims();
      if (!mounted) return;
      setState(() {
        _board = board;
        _claims = claims;
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
                  onTap: () =>
                      ref.read(adminPlaceProvider.notifier).open(house.id),
                ),
              ),
          if (_claims.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Reivindicações pendentes',
              key: const Key('admin-reivindicacoes'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final claim in _claims)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(claim.venueName),
                      Text(claim.claimantLabel),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            key: Key('admin-aprovar-claim-${claim.id}'),
                            onPressed: () => _reviewClaim(claim.id, 'approved'),
                            child: const Text('Aprovar'),
                          ),
                          OutlinedButton(
                            key: Key('admin-recusar-claim-${claim.id}'),
                            onPressed: () => _reviewClaim(claim.id, 'rejected'),
                            child: const Text('Recusar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _reviewClaim(String id, String decision) async {
    try {
      await ref.read(adminApiProvider).reviewVenueClaim(id, decision);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = adminErrorText(error));
      return;
    }
    await _load();
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
  int _total = 0;
  int _offset = 0;
  bool _includeTest = false;
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
      final players = await api.searchPlayers(
        query: _query.text,
        includeTest: _includeTest,
        offset: _offset,
      );
      final queue = await api.referralQueue();
      if (!mounted) return;
      setState(() {
        _players = players.rows;
        _total = players.total;
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
          Text(
            'Contas indicadas em revisão',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
            decoration: const InputDecoration(
              labelText: 'Nome, e-mail ou usuário',
            ),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          FilterChip(
            label: const Text('Mostrar teste'),
            selected: _includeTest,
            onSelected: (value) {
              setState(() {
                _includeTest = value;
                _offset = 0;
              });
              _load();
            },
          ),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!),
          Text(
            '$_total jogadores neste recorte.',
            key: const Key('admin-jogadores-total'),
          ),
          for (final player in _players)
            Card(
              child: ListTile(
                title: Text(player.name),
                subtitle: Text(
                  '${player.email}${player.suspended ? ' · suspenso' : ''}',
                ),
                onTap: () =>
                    ref.read(adminPlaceProvider.notifier).open(player.id),
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: _offset == 0
                    ? null
                    : () {
                        setState(
                          () => _offset = (_offset - 40).clamp(0, _offset),
                        );
                        _load();
                      },
                child: const Text('Anterior'),
              ),
              TextButton(
                key: const Key('admin-jogadores-proxima'),
                onPressed: _offset + _players.length >= _total
                    ? null
                    : () {
                        setState(() => _offset += 40);
                        _load();
                      },
                child: const Text('Próxima'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decide(ReviewRow row, String decision) async {
    try {
      await ref
          .read(adminApiProvider)
          .decideReferral(
            userId: row.userId,
            venueId: row.venueId,
            decision: decision,
          );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = adminErrorText(error));
      return;
    }
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
  PlayerLedger? _ledger;
  String? _error;
  String? _notice;
  bool _busy = false;
  final _points = TextEditingController();
  final _reason = TextEditingController();
  bool _playerTest = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _points.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final PlayerProfile player;
    try {
      player = await ref.read(adminApiProvider).player(widget.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = adminErrorText(error));
      return;
    }
    PlayerLedger? ledger;
    try {
      ledger = await ref.read(adminPeopleProvider).ledger(widget.id);
    } on Object {
      ledger = null;
    }
    if (!mounted) return;
    setState(() {
      _player = player;
      _ledger = ledger;
      _playerTest = ledger?.isTest ?? false;
    });
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _error = error ? text : null;
      _notice = error ? null : text;
    });
  }

  /// Roda a ação, relê o jogador e diz na tela o que houve.
  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      try {
        await action();
      } on Object catch (error) {
        _say(adminErrorText(error), error: true);
        return;
      }
      await _load();
      _say(done);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pointsMove(String direction) async {
    final points = int.tryParse(_points.text.trim());
    if (points == null || points < 1 || _reason.text.trim().length < 3) {
      _say('Informe os pontos e um motivo (3 letras ou mais).', error: true);
      return;
    }
    final okWord = await confirmTyped(
      context,
      title: 'PONTOS',
      body: direction == 'credit'
          ? 'Credita $points pontos na hora, com o motivo no livro.'
          : 'Debita $points pontos se houver saldo livre.',
      word: 'PONTOS',
    );
    if (!okWord || !mounted) return;
    await _run(() async {
      await ref
          .read(adminPeopleProvider)
          .adjustPoints(
            userId: widget.id,
            points: points,
            direction: direction,
            reason: _reason.text.trim(),
            confirm: 'PONTOS',
          );
      _points.clear();
      _reason.clear();
    }, direction == 'credit' ? '$points pontos creditados.' : '$points pontos debitados.');
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
      banner: player != null && (_error != null || _notice != null)
          ? AdminNotice(
              textKey: const Key('admin-jogador-aviso'),
              text: _error ?? _notice!,
              error: _error != null,
              onClose: () => setState(() {
                _error = null;
                _notice = null;
              }),
            )
          : null,
      child: player == null
          ? Text(
              _error ?? 'Carregando jogador…',
              key: const Key('admin-jogador-aviso'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${player.email} · @${player.username}'),
                Text(
                  'Nível ${player.tier} · comissão ${percentBps(player.tierBonusBps)} · ${player.activeReferrals} indicações ativas',
                ),
                Text(
                  'Código ${player.referralCode.isEmpty ? '—' : player.referralCode}',
                ),
                Text(
                  'Saldo ${player.availablePoints} pontos (${reais(player.availablePoints * player.pointValueCents)}) · ${player.pendingPoints} a liberar',
                ),
                if (player.referredBy.isNotEmpty)
                  Text('Entrou pelo código ${player.referredBy}'),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('admin-jogador-suspender'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(adminApiProvider)
                              .suspendPlayer(player.id, !player.suspended),
                          player.suspended
                              ? 'Conta reativada.'
                              : 'Conta suspensa.',
                        ),
                  child: Text(
                    player.suspended ? 'Reativar conta' : 'Suspender conta',
                  ),
                ),
                SwitchListTile(
                  key: const Key('admin-jogador-teste'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Conta de teste'),
                  value: _playerTest,
                  onChanged: _busy
                      ? null
                      : (value) => _run(
                          () => ref
                              .read(adminPeopleProvider)
                              .setTest(
                                kind: 'player',
                                id: player.id,
                                enabled: value,
                              ),
                          value
                              ? 'Conta marcada como teste.'
                              : 'Conta deixou de ser de teste.',
                        ),
                ),
                TextField(
                  key: const Key('admin-pontos'),
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pontos'),
                ),
                TextField(
                  key: const Key('admin-pontos-motivo'),
                  controller: _reason,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const Key('admin-pontos-credito'),
                      onPressed: _busy ? null : () => _pointsMove('credit'),
                      child: const Text('Creditar'),
                    ),
                    TextButton(
                      key: const Key('admin-pontos-debito'),
                      onPressed: _busy ? null : () => _pointsMove('debit'),
                      child: const Text('Debitar'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Reservas'),
                for (final line in player.reservations) Text(line),
                const SizedBox(height: 12),
                const Text('Extrato de Scape Points'),
                for (final line in player.entries) Text(line),
                for (final line in _ledger?.lines ?? const <String>[])
                  Text(line),
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
  final _passportInputs = <String, TextEditingController>{};
  bool _blockSelf = true;
  bool _passportOn = false;
  bool _freeSlot = false;
  String? _message;
  String? _passportMessage;

  @override
  void initState() {
    super.initState();
    for (final field in rewardFields) {
      _fields[field.id] = TextEditingController();
    }
    for (final field in passportRuleFields) {
      _passportInputs[field.id] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final controller in _passportInputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(adminApiProvider);
    final Map<String, Object?> settings;
    final List<Map<String, Object?>> history;
    final Map<String, Object?> passport;
    try {
      settings = await api.rewardSettings();
      history = await api.rewardHistory();
      passport = await api.passportSettings();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
      return;
    }
    if (!mounted) return;
    for (final field in rewardFields) {
      _fields[field.id]!.text = '${settings[field.id] ?? ''}';
    }
    for (final field in passportRuleFields) {
      _passportInputs[field.id]!.text = '${passport[field.id] ?? ''}';
    }
    setState(() {
      _settings = settings;
      _history = history;
      _blockSelf = settings['block_self_payer'] == true;
      _passportOn = passport['passport_enabled'] == true;
      _freeSlot = settings['backed_full_slot_enabled'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminFrame(
      key: const Key('admin-regras'),
      title: 'Comissões e recompensas',
      child: _settings == null
          ? Text(
              _message ?? 'Carregando regras…',
              key: const Key('admin-regras-aviso'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Estes números definem as recompensas do EscapeMatch. O campo guarda o valor da regra. Ao lado, a leitura em porcentagem, em pontos ou na unidade certa. O jogador vê pontos no app. Cada gravação fica no histórico.',
                  key: Key('admin-regras-intro'),
                ),
                const SizedBox(height: 12),
                for (final field in rewardFields) ...[
                  if (field.section != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      field.section!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: adminTeal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  RewardRuleTile(
                    field: field,
                    controller: _fields[field.id]!,
                    pointValueCents: int.tryParse(
                      _fields['point_value_cents']!.text.trim(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permitir vaga grátis com pontos'),
                  subtitle: const Text(
                    'Desligada por padrão. Ligada, pontos de indicação e de cashback já liberados podem cobrir a vaga, sem limite mensal. O que passar da comissão vira crédito da casa no próximo repasse. Boas-vindas e promoção continuam no teto.',
                  ),
                  value: _freeSlot,
                  onChanged: (value) => setState(() => _freeSlot = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Travar quando o pagador é o próprio indicador',
                  ),
                  subtitle: const Text(
                    'Se quem paga é quem indicou, aquela indicação não é lançada.',
                  ),
                  value: _blockSelf,
                  onChanged: (value) => setState(() => _blockSelf = value),
                ),
                FilledButton(
                  key: const Key('admin-salvar-regras'),
                  onPressed: _save,
                  child: const Text('Salvar regras'),
                ),
                if (_message != null)
                  Text(
                    _message!,
                    key: const Key('admin-regras-aviso'),
                    style: _message == 'Regras gravadas.'
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Passaporte de salas',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: adminTeal, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A flag nasce desligada. Os pontos do marco são sem lastro, como boas-vindas e promoção: só desconto, até o teto. Não pagam a vaga inteira. Casa com uma sala não ganha o marco de fechar a casa.',
                  key: Key('admin-passaporte-intro'),
                ),
                SwitchListTile(
                  key: const Key('admin-passaporte-flag'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Passaporte ligado'),
                  value: _passportOn,
                  onChanged: (value) => setState(() => _passportOn = value),
                ),
                for (final field in passportRuleFields) ...[
                  TextField(
                    key: Key('admin-passaporte-${field.id}'),
                    controller: _passportInputs[field.id],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: field.label),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  key: const Key('admin-salvar-passaporte'),
                  onPressed: _savePassport,
                  child: const Text('Salvar passaporte'),
                ),
                if (_passportMessage != null)
                  Text(
                    _passportMessage!,
                    key: const Key('admin-passaporte-aviso'),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Histórico',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_history.isEmpty) const Text('Nenhuma alteração ainda.'),
                for (final row in _history.take(8))
                  Text(
                    '${whenLabel(DateTime.tryParse('${row['created_at'] ?? ''}'))} · alteração registrada',
                  ),
                const SizedBox(height: 24),
                const CheckoutDesk(),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final empty = [
      for (final field in rewardFields)
        if (int.tryParse(_fields[field.id]!.text.trim()) == null) field.label,
    ];
    if (empty.isNotEmpty) {
      setState(() {
        _message =
            'Preencha todos os campos antes de salvar. Campo vazio não vira zero. Faltando: ${empty.join(', ')}.';
      });
      return;
    }
    final patch = <String, Object?>{
      for (final field in rewardFields)
        field.id: int.tryParse(_fields[field.id]!.text.trim()) ?? 0,
      'block_self_payer': _blockSelf,
      'backed_full_slot_enabled': _freeSlot,
    };
    try {
      await ref.read(adminApiProvider).saveRewardSettings(patch);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
      return;
    }
    await _load();
    if (!mounted) return;
    setState(() => _message = 'Regras gravadas.');
  }

  Future<void> _savePassport() async {
    final empty = [
      for (final field in passportRuleFields)
        if (int.tryParse(_passportInputs[field.id]!.text.trim()) == null)
          field.label,
    ];
    if (empty.isNotEmpty) {
      setState(() {
        _passportMessage =
            'Preencha todos os campos antes de salvar. Faltando: ${empty.join(', ')}.';
      });
      return;
    }
    final patch = <String, Object?>{
      'passport_enabled': _passportOn,
      for (final field in passportRuleFields)
        field.id: int.tryParse(_passportInputs[field.id]!.text.trim()) ?? 0,
    };
    try {
      await ref.read(adminApiProvider).savePassportSettings(patch);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _passportMessage = adminErrorText(error));
      return;
    }
    await _load();
    if (!mounted) return;
    setState(() => _passportMessage = 'Passaporte gravado.');
  }
}

class PassportRuleField {
  const PassportRuleField({required this.id, required this.label});

  final String id;
  final String label;
}

const passportRuleFields = <PassportRuleField>[
  PassportRuleField(id: 'passport_rooms_5', label: 'Salas do primeiro marco'),
  PassportRuleField(id: 'passport_points_5', label: 'Pontos do primeiro marco'),
  PassportRuleField(id: 'passport_rooms_10', label: 'Salas do segundo marco'),
  PassportRuleField(id: 'passport_points_10', label: 'Pontos do segundo marco'),
  PassportRuleField(id: 'passport_rooms_25', label: 'Salas do terceiro marco'),
  PassportRuleField(
    id: 'passport_points_25',
    label: 'Pontos do terceiro marco',
  ),
  PassportRuleField(
    id: 'passport_house_points',
    label: 'Pontos ao fechar a casa',
  ),
];

class GanhosPage extends ConsumerStatefulWidget {
  const GanhosPage({super.key});

  @override
  ConsumerState<GanhosPage> createState() => _GanhosPageState();
}

class _GanhosPageState extends ConsumerState<GanhosPage> {
  EarningsReport? _report;
  ScapeLiability? _liability;
  String? _liabilityError;
  String? _reportError;
  String _period = 'tudo';
  bool _includeTest = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now().toUtc();
    DateTime? from;
    if (_period == '30') from = now.subtract(const Duration(days: 30));
    // "Este mês" começa à meia-noite de Brasília, não à meia-noite UTC.
    if (_period == 'mes') from = brasiliaMonthStartUtc(now);
    final api = ref.read(adminApiProvider);
    final EarningsReport report;
    try {
      report = await api.earnings(from: from, includeTest: _includeTest);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _reportError = adminErrorText(error));
      return;
    }
    ScapeLiability? liability;
    String? liabilityError;
    try {
      liability = await api.scapeLiability();
    } on Object {
      liabilityError = 'Não foi possível ler o passivo de pontos.';
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _reportError = null;
      _liability = liability;
      _liabilityError = liabilityError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final liability = _liability;
    return AdminFrame(
      key: const Key('admin-ganhos'),
      title: 'Ganhos',
      child: report == null
          ? Text(
              _reportError ?? 'Carregando ganhos…',
              key: const Key('admin-ganhos-aviso'),
            )
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
                    FilterChip(
                      key: const Key('admin-ganhos-teste'),
                      label: const Text('Mostrar teste'),
                      selected: _includeTest,
                      onSelected: (value) {
                        setState(() => _includeTest = value);
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
                const SizedBox(height: 8),
                Text(
                  'Subsídio ${reais(report.rewardsSubsidyCents)} · pontos usados ${reais(report.rewardsPointsCents)}. O total usa o maior dos dois, para não contar o mesmo valor duas vezes.',
                  key: const Key('admin-recompensas-partes'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Passivo de pontos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (liability == null)
                  Text(_liabilityError ?? 'Carregando passivo…')
                else ...[
                  Text(
                    '${formatPoints(liability.unusedPoints)} pontos ainda não usados · ${reais(liability.unusedCents)}.',
                    key: const Key('admin-passivo'),
                  ),
                  Text(
                    '${formatPoints(liability.pendingPoints)} pendentes e ${formatPoints(liability.availablePoints)} disponíveis.',
                  ),
                  Text(
                    'Crédito de casa ainda pendente: ${reais(liability.venueCreditPendingCents)}.',
                  ),
                ],
                const SizedBox(height: 16),
                if (report.pagbankFeeCents == null)
                  const Text(
                    'A taxa do PagBank ainda não chegou neste recorte. O painel não estima esse valor.',
                    key: Key('admin-taxa-ausente'),
                  )
                else
                  Text(
                    'Taxa do PagBank, paga pela comissão do EscapeMatch: ${reais(report.pagbankFeeCents!)} em ${report.pagbankFeeRows} cobranças.',
                    key: const Key('admin-taxa-pagbank'),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Por casa',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
  String? _message;
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
    final HighlightsBoard board;
    try {
      board = await ref.read(adminApiProvider).highlights();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
      return;
    }
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
          ? Text(
              _message ?? 'Carregando destaques…',
              key: const Key('admin-destaques-aviso'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O número menor aparece antes na home do jogador. Vazio tira o item da seleção.',
                ),
                if (_message != null)
                  Text(_message!, key: const Key('admin-destaques-aviso')),
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
    final rank = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (rank == null || rank < 1)) {
      // Antes, um texto inválido virava "sem número" e tirava o item.
      setState(() {
        _message =
            'A ordem é um número inteiro a partir de 1. Vazio tira o item.';
      });
      return;
    }
    try {
      await ref.read(adminApiProvider).setHighlight(kind, id, rank);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
      return;
    }
    if (!mounted) return;
    setState(() => _message = 'Ordem gravada.');
    await _load();
  }
}

class AuditoriaPage extends ConsumerStatefulWidget {
  const AuditoriaPage({super.key});

  @override
  ConsumerState<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends ConsumerState<AuditoriaPage> {
  final _action = TextEditingController();
  final _actor = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  JsonPage _rows = const JsonPage(total: 0, rows: []);
  JsonPage _commission = const JsonPage(total: 0, rows: []);
  JsonPage _rules = const JsonPage(total: 0, rows: []);
  int _offset = 0;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _action.dispose();
    _actor.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  DateTime? _day(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  Future<void> _load() async {
    final api = ref.read(adminApiProvider);
    try {
      final rows = await api.searchAudit(
        action: _action.text,
        actor: _actor.text,
        from: _day(_from.text),
        to: _day(_to.text),
        offset: _offset,
      );
      final commission = await api.commissionHistory();
      final rules = await api.ruleHistory();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _commission = commission;
        _rules = rules;
        _error = null;
        _loaded = true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = adminErrorText(error));
    }
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
          TextField(
            key: const Key('admin-auditoria-acao'),
            controller: _action,
            decoration: const InputDecoration(labelText: 'Ação'),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          TextField(
            key: const Key('admin-auditoria-admin'),
            controller: _actor,
            decoration: const InputDecoration(labelText: 'Admin'),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          TextField(
            controller: _from,
            decoration: const InputDecoration(labelText: 'De (AAAA-MM-DD)'),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          TextField(
            controller: _to,
            decoration: const InputDecoration(labelText: 'Até (AAAA-MM-DD)'),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
          if (_error != null)
            Text(_error!, key: const Key('admin-auditoria-aviso')),
          if (_error == null && !_loaded) const Text('Carregando auditoria…'),
          if (_error == null && _loaded && _rows.rows.isEmpty)
            const Text('Nenhuma ação ainda.'),
          if (_error == null && _loaded)
            Text('${_rows.total} ações neste recorte.'),
          for (final row in _rows.rows)
            Card(
              child: ListTile(
                title: Text('${row['action']} · ${row['target_table']}'),
                subtitle: Text(
                  '${whenLabel(DateTime.tryParse('${row['created_at']}'))}'
                  '${_who(row)} · ${row['target_id']}\n'
                  'antes ${row['before']}\ndepois ${row['after']}',
                ),
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: _offset == 0
                    ? null
                    : () {
                        setState(
                          () => _offset = (_offset - 40).clamp(0, _offset),
                        );
                        _load();
                      },
                child: const Text('Anterior'),
              ),
              TextButton(
                onPressed: _offset + _rows.rows.length >= _rows.total
                    ? null
                    : () {
                        setState(() => _offset += 40);
                        _load();
                      },
                child: const Text('Próxima'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Histórico de comissão',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_commission.rows.isEmpty)
            const Text('Nenhuma mudança de comissão.'),
          for (final row in _commission.rows)
            Text(
              '${row['venue_name']}: ${row['before_bps']} → ${row['after_bps']} bps'
              '${_who(row)}',
              key: const Key('admin-comissao-historico'),
            ),
          const SizedBox(height: 16),
          Text(
            'Histórico de regras',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Inclui o que entrou por migration ou SQL direto, sem sessão de admin.',
          ),
          if (_rules.rows.isEmpty) const Text('Nenhuma mudança de regra.'),
          for (final row in _rules.rows)
            Text(
              '${row['table_name']} · ${row['operation']}'
              '${_who(row).isEmpty ? ' · SQL direto' : _who(row)}',
              key: const Key('admin-regra-historico'),
            ),
        ],
      ),
    );
  }

  String _who(Map<String, Object?> row) {
    final name = '${row['actor_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return ' · $name';
    final id = '${row['actor_id'] ?? ''}'.trim();
    if (id.isEmpty) return '';
    return ' · ${id.length > 8 ? id.substring(0, 8) : id}';
  }
}

class CheckoutDesk extends ConsumerStatefulWidget {
  const CheckoutDesk({super.key});

  @override
  ConsumerState<CheckoutDesk> createState() => _CheckoutDeskState();
}

class _CheckoutDeskState extends ConsumerState<CheckoutDesk> {
  final _max = TextEditingController();
  final _pix = TextEditingController();
  final _card = TextEditingController();
  final _bps = TextEditingController();
  bool _reads = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _max.dispose();
    _pix.dispose();
    _card.dispose();
    _bps.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await ref.read(adminApiProvider).checkoutSettings();
      if (!mounted) return;
      setState(() {
        _max.text = '${settings.maxInterestFree}';
        _pix.text = '${settings.pixFeeCents}';
        _card.text = '${settings.cardFeeCents}';
        _bps.text = '${settings.cardFeeBps}';
        _reads = settings.chargeReadsConfig;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
    }
  }

  Future<void> _save() async {
    final max = int.tryParse(_max.text.trim());
    final pix = int.tryParse(_pix.text.trim());
    final card = int.tryParse(_card.text.trim());
    final bps = int.tryParse(_bps.text.trim());
    if (max == null || pix == null || card == null || bps == null) {
      setState(() => _message = 'Preencha os quatro números.');
      return;
    }
    final okWord = await confirmTyped(
      context,
      title: 'CONFIG',
      body: 'As taxas de recibo passam a valer na hora. O limite de parcelas fica guardado; a cobrança ainda lê o limite no código dela.',
      word: 'CONFIG',
    );
    if (!okWord || !mounted) return;
    try {
      await ref
          .read(adminApiProvider)
          .saveCheckout(
            confirm: 'CONFIG',
            maxInterestFree: max,
            pixFeeCents: pix,
            cardFeeCents: card,
            cardFeeBps: bps,
          );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = adminErrorText(error));
      return;
    }
    if (!mounted) return;
    setState(() => _message = 'Configuração gravada.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('admin-checkout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Parcelas e taxas de recibo',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          _reads ? 'A cobrança já lê este limite.' : 'A regra vigente continua no código da cobrança: até 3x sem juros e 4x ou mais recusado. Este campo guarda o número (padrão 3) para a função passar a lê-lo. Este painel não altera essa função.',
          key: const Key('admin-checkout-aviso'),
        ),
        TextField(
          key: const Key('admin-checkout-parcelas'),
          controller: _max,
          decoration: const InputDecoration(labelText: 'Parcelas sem juros'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _pix,
          decoration: const InputDecoration(
            labelText: 'Taxa do recibo no Pix, em centavos',
          ),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _card,
          decoration: const InputDecoration(
            labelText: 'Taxa fixa do recibo no cartão, em centavos',
          ),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _bps,
          decoration: const InputDecoration(
            labelText: 'Taxa percentual do recibo no cartão, em bps',
          ),
          keyboardType: TextInputType.number,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('admin-checkout-gravar'),
            onPressed: _save,
            child: const Text('Gravar parcelas e taxas'),
          ),
        ),
        if (_message != null) Text(_message!),
      ],
    );
  }
}

class AdminFrame extends StatelessWidget {
  const AdminFrame({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.banner,
  });

  final String title;
  final Widget child;
  final Widget? leading;

  /// Aviso que fica fixo acima da rolagem (resultado de um botão).
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          children: [
            if (banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: banner,
              ),
            Expanded(
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
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
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
