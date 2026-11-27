import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_city_field.dart';
import 'package:scapematch_admin/admin_confirm.dart';
import 'package:scapematch_admin/admin_errors.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_notice.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:scapematch_admin/admin_people.dart';
import 'package:scapematch_admin/admin_place.dart';

const _categories = <(String, String)>[
  ('escape-room', 'Escape room'),
  ('rpg', 'RPG'),
  ('board-game', 'Jogo de tabuleiro'),
  ('laser-tag', 'Laser tag'),
  ('immersive', 'Experiência imersiva'),
];

/// Tela da casa. Cada botão grava no servidor, relê a casa e diz na própria
/// tela, no aviso fixo do alto, o que aconteceu ou por que recusou.
class CasaPage extends ConsumerStatefulWidget {
  const CasaPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<CasaPage> createState() => _CasaPageState();
}

class _CasaPageState extends ConsumerState<CasaPage> {
  VenueProfile? _house;
  String? _message;
  bool _messageIsError = false;

  /// Nome da ação em andamento. Enquanto houver uma, os botões esperam:
  /// toque duplo não manda a mesma gravação duas vezes.
  String? _busy;
  final _name = TextEditingController();
  final _neighborhood = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _postal = TextEditingController();
  final _phone = TextEditingController();
  final _badge = TextEditingController();
  final _bps = TextEditingController();
  final _platform = TextEditingController();
  final _mergeTarget = TextEditingController();
  final _officialEmail = TextEditingController();
  final _officialPhone = TextEditingController();
  String _category = 'escape-room';
  String _cityId = '';
  String _cityLabel = '';
  String _cityState = '';
  String? _mergeTargetId;
  List<VenueRow> _targets = const [];

  @override
  void initState() {
    super.initState();
    _firstLoad();
    _loadTargets();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _neighborhood,
      _street,
      _number,
      _postal,
      _phone,
      _badge,
      _bps,
      _platform,
      _mergeTarget,
      _officialEmail,
      _officialPhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _firstLoad() async {
    try {
      await _reload();
    } on Object catch (error) {
      _say(adminErrorText(error), error: true);
    }
  }

  /// Casas que podem receber a mescla. Se a lista falhar, a tela cai para o
  /// campo de id.
  Future<void> _loadTargets() async {
    try {
      final board = await ref.read(adminApiProvider).venues();
      if (!mounted) return;
      setState(() {
        _targets = [
          for (final row in board.houses)
            if (row.id != widget.id &&
                (row.status == 'approved' || row.status == 'pending'))
              row,
        ];
      });
    } on Object {
      // Sem lista, fica o campo de id.
    }
  }

  /// Relê a casa no servidor e devolve o que ele guardou para os campos.
  /// [only] limita quais blocos de campos são reescritos, para não apagar o
  /// que o Nícolas está digitando em outro bloco.
  Future<void> _reload({Set<String>? only}) async {
    final house = await ref.read(adminApiProvider).venue(widget.id);
    if (!mounted) return;
    bool take(String block) => only == null || only.contains(block);
    if (take('dados')) {
      _name.text = house.name;
      _neighborhood.text = house.neighborhood;
      _street.text = house.streetAddress;
      _number.text = house.addressNumber;
      _postal.text = house.postalCode;
      _phone.text = house.phone;
      _badge.text = house.badge;
      _category = house.category;
      _cityId = house.cityId;
      _cityState = house.cityStateCode;
      _cityLabel = _labelFor(house);
    }
    if (take('comissao') || take('plataforma')) {
      _bps.text = percentInput(house.commissionBps);
    }
    if (take('plataforma')) _platform.text = percentInput(house.platformBps);
    if (take('contato')) {
      _officialEmail.text = house.officialEmail;
      _officialPhone.text = house.officialPhone;
    }
    setState(() => _house = house);
  }

  String _labelFor(VenueProfile house) {
    if (house.cityName.isEmpty) return house.cityId;
    return house.cityStateCode.isEmpty
        ? house.cityName
        : '${house.cityName} · ${house.cityStateCode}';
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  /// Grava, relê e avisa. Qualquer erro vira texto na tela, nunca silêncio.
  Future<void> _run(
    String name,
    Future<void> Function() write, {
    required String done,
    Set<String>? reload,
  }) async {
    if (_busy != null) return;
    setState(() {
      _busy = name;
      _message = null;
    });
    try {
      try {
        await write();
      } on Object catch (error) {
        _say(adminErrorText(error), error: true);
        return;
      }
      try {
        await _reload(only: reload);
      } on Object catch (error) {
        _say(
          'Gravou, mas não deu para reler a casa: ${adminErrorText(error)}',
          error: true,
        );
        return;
      }
      _say(done);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  VoidCallback? _tap(VoidCallback action) => _busy == null ? action : null;

  String _label(String name, String idle, String working) {
    return _busy == name ? working : idle;
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
      banner: house != null && _message != null
          ? AdminNotice(
              textKey: const Key('admin-casa-aviso'),
              text: _message!,
              error: _messageIsError,
              onClose: () => setState(() => _message = null),
            )
          : null,
      child: house == null ? _loading() : _content(house),
    );
  }

  Widget _loading() {
    final error = _message != null && _messageIsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _message ?? 'Carregando casa…',
          key: const Key('admin-casa-aviso'),
        ),
        if (error)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('admin-casa-recarregar'),
              onPressed: () {
                setState(() => _message = null);
                _firstLoad();
              },
              child: const Text('Tentar de novo'),
            ),
          ),
      ],
    );
  }

  Widget _content(VenueProfile house) {
    final categories = [
      ..._categories,
      if (!_categories.any((item) => item.$1 == _category))
        (_category, _category),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${casaStatusLabel(house)} · ${_labelFor(house)} · ${house.ownerName} · ${house.ownerEmail}',
        ),
        if (house.isTest)
          const Text(
            'Casa de teste: não aparece para jogador nem nos números.',
          ),
        if (house.mergedInto.isNotEmpty)
          Text('Mesclada na casa ${house.mergedInto}.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('admin-casa-operacao'),
            onPressed: () => ref
                .read(adminPlaceProvider.notifier)
                .openSection(AdminSection.operacao, house.id),
            child: const Text('Salas e sessões'),
          ),
        ),
        Text(
          '${house.documentKind.toUpperCase()} final ${house.documentLast4} · ${house.phone}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (house.status == 'pending') ...[
              FilledButton(
                key: const Key('admin-aprovar'),
                onPressed: _tap(() => _review('approved')),
                child: const Text('Aprovar'),
              ),
              OutlinedButton(
                onPressed: _tap(() => _review('rejected')),
                child: const Text('Reprovar'),
              ),
            ],
            if (house.status == 'approved')
              OutlinedButton(
                key: const Key('admin-suspender'),
                onPressed: _tap(
                  () => _run(
                    'suspender',
                    () => ref
                        .read(adminApiProvider)
                        .suspendVenue(house.id, !house.suspended),
                    done: house.suspended ? 'Casa reativada.' : 'Casa suspensa. Ela some para o jogador até reativar.',
                  ),
                ),
                child: Text(house.suspended ? 'Reativar' : 'Suspender'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Comissão desta casa, em percentual. A cobrança já feita guarda o percentual dela.',
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('admin-comissao'),
          controller: _bps,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Comissão (%)',
            helperText: 'De 0 a 30. Exemplo: 22,5',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('admin-gravar-comissao'),
            onPressed: _tap(_commission),
            child: Text(_label('comissao', 'Gravar comissão', 'Gravando…')),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Snapshots das reservas'),
        for (final snap in house.snapshots)
          Text(
            '${snap.status} · ${percentBps(snap.commissionBps)} · ${snap.id}',
          ),
        const SizedBox(height: 16),
        const Text(
          'Contato oficial da reivindicação. O código vai só para estes campos, não para o que o dono digitar no cadastro.',
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('admin-contato-email'),
          controller: _officialEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail oficial'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('admin-contato-telefone'),
          controller: _officialPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Telefone oficial'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('admin-gravar-contato'),
            onPressed: _tap(_contacts),
            child: Text(
              _label('contato', 'Gravar contato oficial', 'Gravando…'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('admin-casa-nome'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        TextField(
          controller: _street,
          decoration: const InputDecoration(labelText: 'Endereço'),
        ),
        TextField(
          controller: _number,
          decoration: const InputDecoration(labelText: 'Número'),
        ),
        TextField(
          key: const Key('admin-casa-cep'),
          controller: _postal,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'CEP',
            helperText: '8 números. O hífen é tirado ao gravar.',
          ),
        ),
        TextField(
          controller: _neighborhood,
          decoration: const InputDecoration(labelText: 'Bairro'),
        ),
        const SizedBox(height: 12),
        AdminCityField(
          key: ValueKey('admin-cidade-${house.id}'),
          selectedId: _cityId,
          selectedLabel: _cityLabel,
          initialState: _cityState,
          enabled: _busy == null,
          load: ref.read(adminApiProvider).cities,
          onSelected: (city) => setState(() {
            _cityId = city.id;
            _cityLabel = '${city.name} · ${city.stateCode}';
            _cityState = city.stateCode;
          }),
        ),
        TextField(
          key: const Key('admin-casa-telefone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Telefone',
            helperText: 'Com DDD. Os símbolos são tirados ao gravar.',
          ),
        ),
        DropdownButtonFormField<String>(
          key: const Key('admin-casa-categoria'),
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: [
            for (final item in categories)
              DropdownMenuItem(value: item.$1, child: Text(item.$2)),
          ],
          onChanged: _busy == null
              ? (value) => setState(() => _category = value ?? _category)
              : null,
        ),
        TextField(
          controller: _badge,
          decoration: const InputDecoration(labelText: 'Selo'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('admin-salvar-casa'),
            onPressed: _tap(_saveData),
            child: Text(_label('dados', 'Salvar dados', 'Gravando…')),
          ),
        ),
        if (house.status == 'rejected')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('admin-reabrir-casa'),
              onPressed: _tap(
                () => _run(
                  'reabrir',
                  () => ref.read(adminPeopleProvider).reopenVenue(house.id),
                  done: 'Casa reaberta. Ela voltou para a fila de análise.',
                ),
              ),
              child: const Text('Reabrir casa reprovada'),
            ),
          ),
        SwitchListTile(
          key: const Key('admin-casa-teste'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Casa de teste'),
          value: house.isTest,
          onChanged: _busy == null
              ? (value) => _run(
                  'teste',
                  () => ref
                      .read(adminPeopleProvider)
                      .setTest(kind: 'venue', id: house.id, enabled: value),
                  done: value
                      ? 'Casa marcada como teste.'
                      : 'Casa deixou de ser de teste.',
                )
              : null,
        ),
        _mergeField(house),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('admin-mesclar'),
            onPressed: _tap(() => _merge(house)),
            child: Text(_label('mesclar', 'Mesclar nesta casa', 'Mesclando…')),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('admin-comissao-oficial'),
            onPressed: _tap(() => _backToOfficial(house)),
            child: const Text('Voltar à comissão oficial'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Comissão oficial da plataforma, em percentual. Vale para as casas sem taxa própria.',
        ),
        TextField(
          key: const Key('admin-comissao-plataforma'),
          controller: _platform,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Comissão oficial (%)',
            helperText: 'De 0 a 30. Sem atalho.',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('admin-gravar-plataforma'),
            onPressed: _tap(_platformCommission),
            child: Text(
              _label('plataforma', 'Gravar comissão oficial', 'Gravando…'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mergeField(VenueProfile house) {
    if (_targets.isEmpty) {
      return TextField(
        key: const Key('admin-mesclar-destino'),
        controller: _mergeTarget,
        decoration: const InputDecoration(
          labelText: 'Id da casa que fica',
          helperText: 'Cole o id completo da casa que recebe as salas.',
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: const Key('admin-mesclar-destino'),
      initialValue: _mergeTargetId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Casa que fica',
        helperText: 'A casa de cima passa tudo para a que você escolher.',
      ),
      items: [
        for (final row in _targets)
          DropdownMenuItem(
            value: row.id,
            child: Text(
              '${row.name} · ${row.cityId}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _busy == null
          ? (value) => setState(() => _mergeTargetId = value)
          : null,
    );
  }

  Future<void> _review(String decision) async {
    if (_busy != null) return;
    setState(() {
      _busy = 'analise';
      _message = null;
    });
    final api = ref.read(adminApiProvider);
    try {
      final ReviewResult result;
      try {
        result = await api.reviewVenue(widget.id, decision);
      } on Object catch (error) {
        _say(adminErrorText(error), error: true);
        return;
      }
      String? wallet;
      if (result.needsSubaccount) {
        try {
          wallet = await api.provisionWallet(widget.id);
        } on Object {
          wallet = 'A casa foi aprovada. A subconta PagBank não saiu nesta tentativa.';
        }
        if (wallet != null && wallet.startsWith('https://')) {
          await launchExternalUrl(Uri.parse(wallet));
          wallet = 'Continue na PagBank para ligar a casa.';
        }
      }
      try {
        await _reload();
      } on Object catch (error) {
        _say(
          'Gravou, mas não deu para reler a casa: ${adminErrorText(error)}',
          error: true,
        );
        return;
      }
      _say(
        result.needsSubaccount
            ? (wallet ?? 'Aprovada. Abra o PagBank Connect para ligar a casa.')
            : 'Decisão gravada: ${result.status}.',
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveData() async {
    final cep = _postal.text.replaceAll(RegExp(r'\D'), '');
    final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    final problem = _dataProblem(cep: cep, phone: phone);
    if (problem != null) {
      _say(problem, error: true);
      return;
    }
    await _run(
      'dados',
      () async {
        await ref.read(adminApiProvider).updateVenue(widget.id, {
          'name': _name.text.trim(),
          'street_address': _street.text.trim(),
          'address_number': _number.text.trim(),
          'postal_code': cep,
          'neighborhood': _neighborhood.text.trim(),
          'city_id': _cityId,
          'phone': phone,
          'category': _category,
          'badge': _badge.text.trim(),
        });
      },
      done: 'Dados gravados.',
      reload: {'dados'},
    );
  }

  /// A mesma regra do servidor, dita antes de gastar a ida e volta.
  String? _dataProblem({required String cep, required String phone}) {
    if (_name.text.trim().length < 2) return 'Nome: de 2 a 80 caracteres.';
    if (_street.text.trim().length < 2) {
      return 'Endereço: de 2 a 200 caracteres.';
    }
    if (_number.text.trim().isEmpty) return 'Número: informe o número.';
    if (cep.length != 8) return 'CEP: 8 números, sem hífen.';
    if (_neighborhood.text.trim().length < 2) {
      return 'Bairro: de 2 a 80 caracteres.';
    }
    if (_cityId.isEmpty) return 'Cidade: escolha uma cidade da lista.';
    if (phone.length < 10 || phone.length > 13) {
      return 'Telefone: de 10 a 13 números, com DDD e sem símbolos.';
    }
    return null;
  }

  Future<void> _contacts() async {
    final email = _officialEmail.text.trim();
    final phone = _officialPhone.text.trim();
    if (email.isEmpty && phone.isEmpty) {
      _say('Informe o e-mail ou o telefone oficial.', error: true);
      return;
    }
    await _run(
      'contato',
      () =>
          ref.read(adminApiProvider).setVenueContacts(widget.id, email, phone),
      done: 'Contato oficial gravado.',
      reload: {'contato'},
    );
  }

  Future<void> _commission() async {
    final bps = bpsFromPercent(_bps.text);
    if (bps == null) {
      _say(
        'A comissão fica entre 0% e 30%, com até duas casas decimais.',
        error: true,
      );
      return;
    }
    final label = percentBps(bps);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gravar comissão'),
        content: Text(
          'A comissão desta casa passa a ser $label. As reservas já feitas não mudam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('admin-confirmar-comissao'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      'comissao',
      () => ref
          .read(adminApiProvider)
          .setCommission(venueId: widget.id, bps: bps),
      done: 'Comissão gravada em $label. As reservas antigas não mudam.',
      reload: {'comissao'},
    );
  }

  Future<void> _platformCommission() async {
    final bps = bpsFromPercent(_platform.text);
    if (bps == null) {
      _say('A comissão fica entre 0% e 30%.', error: true);
      return;
    }
    final okWord = await confirmTyped(
      context,
      title: 'COMISSAO',
      body: 'A comissão oficial da plataforma passa a ser ${percentBps(bps)}.',
      word: 'COMISSAO',
    );
    if (!okWord || !mounted) return;
    await _run(
      'plataforma',
      () => ref.read(adminApiProvider).setCommission(bps: bps),
      done: 'Comissão oficial gravada em ${percentBps(bps)}.',
      reload: {'plataforma'},
    );
  }

  Future<void> _backToOfficial(VenueProfile house) async {
    if (!house.commissionOverride) {
      _say(
        'Esta casa já usa a comissão oficial (${percentBps(house.platformBps)}).',
      );
      return;
    }
    final okWord = await confirmTyped(
      context,
      title: 'OFICIAL',
      body: 'Esta casa volta a usar a comissão oficial da plataforma.',
      word: 'OFICIAL',
    );
    if (!okWord || !mounted) return;
    await _run(
      'oficial',
      () => ref.read(adminPeopleProvider).clearCommission(house.id, 'OFICIAL'),
      done: 'A casa voltou a usar a comissão oficial.',
      reload: {'comissao'},
    );
  }

  Future<void> _merge(VenueProfile house) async {
    final target = (_targets.isEmpty ? _mergeTarget.text : _mergeTargetId ?? '')
        .trim();
    if (target.isEmpty) {
      _say('Escolha a casa que fica antes de mesclar.', error: true);
      return;
    }
    if (target == house.id) {
      _say('Escolha uma casa diferente desta.', error: true);
      return;
    }
    var targetName = target;
    for (final row in _targets) {
      if (row.id == target) targetName = row.name;
    }
    final okWord = await confirmTyped(
      context,
      title: 'MESCLAR',
      body:
          'As salas, sessões e cobranças de ${house.name} passam para $targetName. A origem fica marcada como mesclada.',
      word: 'MESCLAR',
    );
    if (!okWord || !mounted) return;
    await _run(
      'mesclar',
      () => ref
          .read(adminPeopleProvider)
          .mergeVenues(house.id, target, 'MESCLAR'),
      done:
          'Casas mescladas. ${house.name} ficou como mesclada em $targetName.',
    );
  }
}

String casaStatusLabel(VenueProfile house) {
  if (house.suspended) return 'suspensa';
  return switch (house.status) {
    'pending' => 'pendente',
    'approved' => 'aprovada',
    'rejected' => 'reprovada',
    'merged' => 'unida a outra',
    final other => other,
  };
}
