import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/features/partner/presentation/municipality_picker.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_claim_client.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';
import 'package:scapematch_parceiro/features/partner/presentation/company_type_field.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_possession_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/domain/brazilian_municipalities.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerVenueScreen extends ConsumerStatefulWidget {
  const PartnerVenueScreen({
    super.key,
    this.addingUnit = false,
    this.prefill,
    this.queuedCities = const [],
    this.sameDocument,
    this.loadTemplate,
  });

  /// Cadastro de outra unidade (outra cidade) por quem já tem casa no login.
  final bool addingUnit;

  /// Dados da casa repetidos da cidade anterior do mesmo cadastro.
  final VenueDraft? prefill;

  /// Cidades escolhidas no mesmo cadastro que ainda faltam, em ordem.
  final List<String> queuedCities;

  /// Escolha da casa: mesmo CNPJ em todas as cidades (true) ou CNPJ próprio
  /// por cidade (false). Nulo: começa em "mesmo CNPJ".
  final bool? sameDocument;

  /// Lê os dados da casa para "Cadastrar outra cidade" sem rascunho. Nos
  /// testes, troca o RPC `my_unit_template`.
  final Future<VenueDraft?> Function(String venueId)? loadTemplate;

  @override
  ConsumerState<PartnerVenueScreen> createState() => _PartnerVenueScreenState();
}

class _PartnerVenueScreenState extends ConsumerState<PartnerVenueScreen> {
  final _name = TextEditingController();
  final _neighborhood = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _cep = TextEditingController();
  final _phone = TextEditingController();
  final _document = TextEditingController();
  final _income = TextEditingController();
  final _invite = TextEditingController();
  final _referral = TextEditingController();
  String _kind = 'cnpj';
  String _companyType = 'LIMITED';
  String _category = 'escape-room';
  String? _cityId = 'curitiba';
  String? _error;
  var _busy = false;
  var _accepted = false;
  var _confirmDuplicate = false;
  List<String> _warnings = const [];
  ClaimableVenue? _claim;
  var _claiming = false;
  final _claims = const VenueClaimClient();
  List<String> _extraCities = const [];
  var _extraPickerRound = 0;
  var _sameDocument = true;
  String _houseDocument = '';
  String _houseKind = 'cnpj';

  /// A escolha de CNPJ aparece ao cadastrar outra cidade ou quando o
  /// cadastro já tem outras cidades na fila.
  bool get _showDocumentChoice => widget.addingUnit || _extraCities.isNotEmpty;

  /// Documento travado no da casa ("mesmo CNPJ em todas").
  bool get _documentLocked =>
      widget.addingUnit && _sameDocument && _houseDocument.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sameDocument = widget.sameDocument ?? true;
    final prefill = widget.prefill;
    if (prefill != null && prefill.documentNumber.isNotEmpty) {
      _houseDocument = prefill.documentNumber;
      _houseKind = prefill.documentKind;
    }
    if (prefill != null) {
      _name.text = prefill.name;
      _phone.text = prefill.phone;
      _document.text = prefill.documentNumber;
      _income.text = prefill.incomeReais;
      _kind = prefill.documentKind;
      _companyType = prefill.companyType;
      _category = prefill.category;
      _cityId = prefill.cityId;
    }
    _extraCities = List.unmodifiable(widget.queuedCities);
    if (widget.addingUnit && prefill == null) _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    final houseId = ref.read(partnerSessionProvider)?.houseId ?? '';
    final load = widget.loadTemplate ?? loadUnitTemplate;
    final template = await load(houseId);
    if (!mounted || template == null) return;
    setState(() {
      if (_name.text.isEmpty) _name.text = template.name;
      if (_phone.text.isEmpty) _phone.text = template.phone;
      if (_income.text.isEmpty) _income.text = template.incomeReais;
      _category = template.category;
      _companyType = template.companyType;
      _houseDocument = template.documentNumber;
      _houseKind = template.documentKind;
      if (_sameDocument) {
        _document.text = _houseDocument;
        _kind = _houseKind;
      }
    });
  }

  void _chooseDocument(bool same) {
    setState(() {
      _sameDocument = same;
      if (!widget.addingUnit) return;
      if (same) {
        _document.text = _houseDocument;
        _kind = _houseKind;
      } else if (_document.text == _houseDocument) {
        _document.clear();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _neighborhood.dispose();
    _street.dispose();
    _number.dispose();
    _cep.dispose();
    _phone.dispose();
    _document.dispose();
    _income.dispose();
    _invite.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final draft = VenueDraft(
      name: _name.text,
      cityId: _cityId ?? '',
      neighborhood: _neighborhood.text,
      street: _street.text,
      number: _number.text,
      postalCode: _cep.text,
      phone: _phone.text,
      documentKind: _kind,
      documentNumber: _document.text,
      companyType: _companyType,
      category: _category,
      incomeReais: _income.text,
      inviteCode: _invite.text,
      referralCode: _referral.text,
    );
    if (!_accepted) {
      setState(() {
        _error = 'Aceite os termos do Parceiro, a privacidade e a política de cancelamento para cadastrar a casa.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await submitVenue(
      draft,
      acceptedTerms: true,
      confirmDuplicate: _confirmDuplicate,
      addingUnit: widget.addingUnit,
    );
    if (!mounted) return;
    if (result.warnings.isNotEmpty) {
      setState(() {
        _busy = false;
        _warnings = result.warnings;
        _confirmDuplicate = true;
        _error = null;
      });
      return;
    }
    if (result.claim != null) {
      setState(() {
        _busy = false;
        _claim = result.claim;
        _error = null;
      });
      return;
    }
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    final session = ref.read(partnerSessionProvider.notifier);
    final navigator = Navigator.of(context);
    final remaining = remainingUnitCities(_extraCities, draft.cityId);
    if (remaining.isNotEmpty) {
      // Próxima cidade do mesmo cadastro: só falta o endereço (e o documento,
      // se a unidade daquela cidade tem o dela).
      final next = PartnerVenueScreen(
        addingUnit: true,
        prefill: draft.forNextCity(
          remaining.first,
          keepDocument: _sameDocument,
        ),
        queuedCities: remaining.skip(1).toList(),
        sameDocument: _sameDocument,
      );
      final route = MaterialPageRoute<void>(builder: (_) => next);
      if (navigator.canPop()) {
        navigator.pushReplacement(route);
      } else {
        navigator.push(route);
      }
      await session.reload();
      return;
    }
    if (navigator.canPop()) navigator.pop();
    await session.reload(venueId: result.venueId);
  }

  @override
  Widget build(BuildContext context) {
    final claim = _claim;
    if (claim != null && _claiming) {
      return AppScaffold(
        appBar: AppBar(title: Text(claim.name)),
        body: VenueClaimDesk(
          venue: claim,
          onSend: () => _claims.send(claim.venueId),
          onConfirm: (code) => _claims.confirm(claim.venueId, code),
          onProvision: () => _claims.provision(claim.venueId),
          onLoadDocuments: () =>
              ref.read(venueDocumentsRepositoryProvider).load(claim.venueId),
          onUploadDocument: (item) async {
            final file = await ref.read(venueDocumentPickerProvider).pick();
            if (file == null) return null;
            return ref
                .read(venueDocumentsRepositoryProvider)
                .upload(
                  venueId: claim.venueId,
                  documentId: item.id,
                  bytes: file.bytes,
                );
          },
          onOpenUrl: launchExternalUrl,
          onSubaccountReady: () async {
            try {
              final row = await scapeSupabase
                  .from('venues')
                  .select('receives_payments')
                  .eq('id', claim.venueId)
                  .maybeSingle();
              return row?['receives_payments'] == true;
            } on Object {
              return false;
            }
          },
          onPixReady: () async {
            try {
              final ready = await scapeSupabase.rpc(
                'venue_finance_ready',
                params: {'p_venue_id': claim.venueId},
              );
              return ready == true;
            } on Object {
              return false;
            }
          },
          onOpenHouse: () {
            ref.read(partnerSessionProvider.notifier).reload();
          },
          onOpenWithdrawals: () {
            ref
                .read(partnerSectionProvider.notifier)
                .select(PartnerSection.withdrawals);
            ref.read(partnerSessionProvider.notifier).reload();
          },
        ),
      );
    }
    return AppScaffold(
      desktopMaxWidth: 640,
      appBar: AppBar(
        title: Text(
          widget.addingUnit ? PartnerMessages.addUnitTitle : 'Cadastro da casa',
        ),
        actions: [
          if (!widget.addingUnit)
            TextButton(
              onPressed: () =>
                  ref.read(partnerSessionProvider.notifier).signOut(),
              child: const Text(PartnerMessages.signOut),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          const Text(
            'A casa entra como pendente. O painel abre depois da aprovação.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: PartnerKeys.partnerVenueName,
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome da casa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          MunicipalityPicker(
            cityId: _cityId,
            cityLabel: 'Cidade',
            stateLabel: 'Estado',
            onChanged: (value) => setState(() => _cityId = value),
          ),
          const SizedBox(height: 12),
          if (widget.addingUnit && widget.prefill != null) ...[
            Text(
              PartnerMessages.nextCityHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          _ExtraCitiesField(
            mainCityId: _cityId,
            cities: _extraCities,
            round: _extraPickerRound,
            onAdd: (id) => setState(() {
              _extraCities = addUnitCity(_extraCities, _cityId, id);
              _extraPickerRound++;
            }),
            onRemove: (id) => setState(() {
              _extraCities = [
                for (final city in _extraCities)
                  if (city != id) city,
              ];
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _neighborhood,
            decoration: const InputDecoration(
              labelText: 'Bairro',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _street,
            decoration: const InputDecoration(
              labelText: 'Rua',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _number,
                  decoration: const InputDecoration(
                    labelText: 'Número',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cep,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'CEP',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_showDocumentChoice) ...[
            Text(
              PartnerMessages.documentChoiceTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: PartnerKeys.partnerDocumentChoice,
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text(PartnerMessages.documentChoiceSame),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(PartnerMessages.documentChoiceOwn),
                ),
              ],
              selected: {_sameDocument},
              onSelectionChanged: (value) => _chooseDocument(value.first),
            ),
            const SizedBox(height: 6),
            Text(
              widget.addingUnit && _sameDocument && _houseDocument.isEmpty
                  ? PartnerMessages.documentChoiceMissing
                  : _sameDocument
                  ? PartnerMessages.documentChoiceSameHint
                  : PartnerMessages.documentChoiceOwnHint,
              key: PartnerKeys.partnerDocumentChoiceHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cnpj', label: Text('CNPJ')),
              ButtonSegment(value: 'cpf', label: Text('CPF')),
            ],
            selected: {_kind},
            onSelectionChanged: _documentLocked
                ? null
                : (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.partnerVenueDocument,
            controller: _document,
            readOnly: _documentLocked,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _kind == 'cpf' ? 'CPF' : 'CNPJ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          CompanyTypeField(
            documentKind: _kind,
            value: _companyType,
            onChanged: (value) => setState(() => _companyType = value),
          ),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in VenueDraft.categories.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _income,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Renda mensal (R\$)',
              helperText: 'O PagBank pede este valor para a conta da casa.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invite,
            decoration: const InputDecoration(
              labelText: 'Código de convite (opcional)',
              hintText: 'ninja-cwb',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _referral,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Código de indicação (opcional)',
              helperText: referralCodeHint(ref.watch(rewardRulesProvider)),
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            value: _accepted,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _accepted = value ?? false;
                      _confirmDuplicate = false;
                      _warnings = const [];
                    });
                  },
            title: const Text(
              'Li e aceito os termos do Parceiro, a privacidade e o reembolso.',
            ),
          ),
          if (claim != null) ...[
            const SizedBox(height: 12),
            VenueClaimOffer(
              venue: claim,
              documentKind: _kind,
              onClaim: () => setState(() => _claiming = true),
            ),
          ],
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(PartnerMessages.duplicateTitle),
            for (final warning in _warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(warning),
              ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          const SizedBox(height: 16),
          FilledButton(
            key: PartnerKeys.partnerVenueSubmit,
            onPressed: _busy ? null : _submit,
            child: Text(
              _warnings.isEmpty
                  ? PartnerMessages.sendVenue
                  : PartnerMessages.submitAnyway,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acrescenta [cityId] às outras cidades do cadastro, sem repetir e sem a
/// cidade principal.
List<String> addUnitCity(
  List<String> cities,
  String? mainCityId,
  String cityId,
) {
  final id = cityId.trim();
  if (id.isEmpty || id == mainCityId || cities.contains(id)) return cities;
  return List.unmodifiable([...cities, id]);
}

/// Cidades que ainda faltam depois de gravar a unidade de [doneCityId].
List<String> remainingUnitCities(List<String> cities, String doneCityId) {
  return [
    for (final city in cities)
      if (city != doneCityId) city,
  ];
}

/// Outras cidades da mesma casa. Cada uma vira uma unidade com endereço
/// próprio, cadastrada logo depois desta, e uma aba no painel.
class _ExtraCitiesField extends StatelessWidget {
  const _ExtraCitiesField({
    required this.mainCityId,
    required this.cities,
    required this.round,
    required this.onAdd,
    required this.onRemove,
  });

  final String? mainCityId;
  final List<String> cities;
  final int round;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.partnerExtraCities,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PartnerMessages.extraCitiesTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(PartnerMessages.extraCitiesHint, style: theme.textTheme.bodySmall),
        if (cities.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in cities)
                InputChip(
                  key: PartnerKeys.partnerExtraCity(id),
                  label: Text(municipalityById(id)?.label ?? id),
                  onDeleted: () => onRemove(id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        MunicipalityPicker(
          key: ValueKey('extra-city-$round'),
          cityId: null,
          cityLabel: PartnerMessages.extraCityLabel,
          stateLabel: 'Estado',
          helperText: null,
          onChanged: (value) {
            if (value.isNotEmpty) onAdd(value);
          },
        ),
      ],
    );
  }
}
