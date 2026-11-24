import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_signup_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Cadastro para receber. No modo A o documento não sai do aparelho.
class VenuePagbankSignupCard extends ConsumerStatefulWidget {
  const VenuePagbankSignupCard({
    super.key,
    required this.venueId,
    this.onOpen,
    this.today,
  });

  final String venueId;
  final void Function(Uri uri)? onOpen;
  final DateTime Function()? today;

  @override
  ConsumerState<VenuePagbankSignupCard> createState() =>
      _VenuePagbankSignupCardState();
}

class _VenuePagbankSignupCardState extends ConsumerState<VenuePagbankSignupCard> {
  final _document = TextEditingController();
  final _company = TextEditingController();
  final _responsibleCpf = TextEditingController();
  final _street = TextEditingController();
  final _number = TextEditingController();
  final _complement = TextEditingController();
  final _locality = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _region = TextEditingController();
  final _name = TextEditingController();
  final _birth = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  var _kind = 'cpf';
  String? _category;
  var _terms = false;
  var _loading = true;
  var _busy = false;
  var _api = false;
  var _phase = _SignupPhase.form;
  String? _error;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _document,
      _company,
      _responsibleCpf,
      _street,
      _number,
      _complement,
      _locality,
      _city,
      _postal,
      _region,
      _name,
      _birth,
      _phone,
      _email,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final view = await ref
          .read(pagbankSignupRepositoryProvider)
          .load(widget.venueId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _api = view.apiEnabled;
        _applyRow(view.signup);
      });
    } on PagbankSignupException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = pagbankSignupMessage(error.code);
      });
    }
  }

  void _applyRow(PagbankSignupRow? row) {
    if (row == null) {
      _phase = _SignupPhase.form;
      return;
    }
    if (row.accountId != null) {
      _accountId = row.accountId;
      _phase = _SignupPhase.activation;
      return;
    }
    if (row.accountStatus == 'exists') {
      _phase = _SignupPhase.exists;
      return;
    }
    if (!_api && row.accountStatus == 'guided') {
      _phase = _SignupPhase.manual;
      return;
    }
    _phase = _SignupPhase.form;
  }

  void _clearSensitive() {
    _document.clear();
    _responsibleCpf.clear();
    _birth.clear();
    _phone.clear();
    _email.clear();
  }

  Future<void> _submit() async {
    final issue = PagbankSignupDraft.issue(
      documentKind: _kind,
      documentNumber: _document.text,
      companyName: _company.text,
      postalCode: _postal.text,
      street: _street.text,
      number: _number.text,
      complement: _complement.text,
      locality: _locality.text,
      city: _city.text,
      regionCode: _region.text,
      responsibleName: _name.text,
      responsibleCpf: _responsibleCpf.text,
      birthDate: _birth.text,
      phone: _phone.text,
      email: _email.text,
      businessCategory: _category,
      termsAccepted: _terms,
      today: widget.today?.call() ?? DateTime.now(),
    );
    if (issue != null) {
      setState(() => _error = pagbankSignupMessage(issue));
      return;
    }
    final draft = PagbankSignupDraft.tryParse(
      documentKind: _kind,
      documentNumber: _document.text,
      companyName: _company.text,
      postalCode: _postal.text,
      street: _street.text,
      number: _number.text,
      complement: _complement.text,
      locality: _locality.text,
      city: _city.text,
      regionCode: _region.text,
      responsibleName: _name.text,
      responsibleCpf: _responsibleCpf.text,
      birthDate: _birth.text,
      phone: _phone.text,
      email: _email.text,
      businessCategory: _category,
      termsAccepted: _terms,
      today: widget.today?.call() ?? DateTime.now(),
    );
    if (draft == null || _category == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(pagbankSignupRepositoryProvider);
    try {
      if (!_api) {
        try {
          await repo.guide(
            venueId: widget.venueId,
            documentKind: draft.documentKind,
            businessCategory: draft.businessCategory,
          );
          if (!mounted) return;
          _clearSensitive();
          setState(() {
            _busy = false;
            _phase = _SignupPhase.manual;
          });
          return;
        } on PagbankSignupException catch (error) {
          if (error.code != 'modo_api') rethrow;
          _api = true;
        }
      }
      final created = await repo.create(widget.venueId, draft);
      if (!mounted) return;
      _clearSensitive();
      setState(() {
        _busy = false;
        _accountId = created.accountId;
        _phase = created.accountStatus == 'exists'
            ? _SignupPhase.exists
            : _SignupPhase.activation;
      });
    } on PagbankSignupException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.code == 'conta_existente' || error.code == 'conta_criada') {
          _clearSensitive();
          _phase = _SignupPhase.exists;
          _error = null;
        } else {
          _error = pagbankSignupMessage(error.code);
        }
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = await ref
          .read(pagbankSignupRepositoryProvider)
          .connect(widget.venueId);
      if (!mounted) return;
      setState(() => _busy = false);
      (widget.onOpen ?? launchExternalUrl)(uri);
    } on PagbankSignupException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = pagbankSignupMessage(error.code);
      });
    }
  }

  void _open(String url) {
    final uri = Uri.parse(url);
    (widget.onOpen ?? launchExternalUrl)(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.pagbankSignup,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.pagbankSignupTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _api
              ? PartnerMessages.pagbankSignupApiBody
              : PartnerMessages.pagbankSignupManualBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: PartnerKeys.pagbankSignupError,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Text(PartnerMessages.pagbankSignupLoading)
        else if (_phase == _SignupPhase.manual)
          _ManualSteps(busy: _busy, onOpen: _open, onConnect: _connect)
        else if (_phase == _SignupPhase.activation)
          _Activation(accountId: _accountId, busy: _busy, onConnect: _connect)
        else if (_phase == _SignupPhase.exists)
          _Exists(busy: _busy, onConnect: _connect)
        else
          _form(theme),
      ],
    );
  }

  Widget _form(ThemeData theme) {
    return Column(
      key: PartnerKeys.pagbankSignupForm,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: PartnerKeys.pagbankSignupCpf,
              label: const Text('CPF'),
              selected: _kind == 'cpf',
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _kind = 'cpf'),
            ),
            ChoiceChip(
              key: PartnerKeys.pagbankSignupCnpj,
              label: const Text('CNPJ'),
              selected: _kind == 'cnpj',
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _kind = 'cnpj'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          PartnerKeys.pagbankSignupDocument,
          _kind == 'cnpj' ? 'CNPJ' : 'CPF',
          _document,
        ),
        _field(PartnerKeys.pagbankSignupCompany, 'Razão social', _company),
        if (_kind == 'cnpj')
          _field(
            PartnerKeys.pagbankSignupResponsibleCpf,
            'CPF de quem responde pela empresa',
            _responsibleCpf,
          ),
        _field(PartnerKeys.pagbankSignupStreet, 'Rua', _street),
        _field(PartnerKeys.pagbankSignupNumber, 'Número', _number),
        _field(PartnerKeys.pagbankSignupComplement, 'Complemento', _complement),
        _field(PartnerKeys.pagbankSignupLocality, 'Bairro', _locality),
        _field(PartnerKeys.pagbankSignupCity, 'Cidade', _city),
        _field(PartnerKeys.pagbankSignupPostal, 'CEP', _postal),
        _field(PartnerKeys.pagbankSignupRegion, 'UF', _region),
        _field(PartnerKeys.pagbankSignupName, 'Nome do responsável', _name),
        _field(
          PartnerKeys.pagbankSignupBirth,
          'Nascimento (AAAA-MM-DD)',
          _birth,
        ),
        _field(PartnerKeys.pagbankSignupPhone, 'Celular', _phone),
        _field(PartnerKeys.pagbankSignupEmail, 'E-mail', _email),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: PartnerKeys.pagbankSignupCategory,
          isExpanded: true,
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Categoria do negócio'),
          items: [
            for (final entry in pagbankBusinessCategoryLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _category = value),
        ),
        CheckboxListTile(
          key: PartnerKeys.pagbankSignupTerms,
          contentPadding: EdgeInsets.zero,
          value: _terms,
          onChanged: _busy
              ? null
              : (value) => setState(() => _terms = value == true),
          title: const Text(PartnerMessages.pagbankSignupTerms),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _open(pagbankTermsUrl),
              child: const Text(PartnerMessages.pagbankSignupTermsLink),
            ),
            TextButton(
              onPressed: () => _open(pagbankPrivacyUrl),
              child: const Text(PartnerMessages.pagbankSignupPrivacyLink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: PartnerKeys.pagbankSignupSubmit,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : _submit,
            child: Text(
              _api
                  ? PartnerMessages.pagbankSignupSubmitApi
                  : PartnerMessages.pagbankSignupSubmitManual,
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(Key key, String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: key,
        controller: controller,
        enabled: !_busy,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _ManualSteps extends StatelessWidget {
  const _ManualSteps({
    required this.busy,
    required this.onOpen,
    required this.onConnect,
  });

  final bool busy;
  final void Function(String url) onOpen;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.pagbankSignupManual,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(PartnerMessages.pagbankSignupManualStepAccount),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupManualStepConnect),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupStays),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: PartnerKeys.pagbankSignupOfficial,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy
                ? null
                : () => onOpen(pagbankOfficialSignupUrl),
            child: const Text(PartnerMessages.pagbankSignupOpenOfficial),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: PartnerKeys.pagbankSignupConnect,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? null : onConnect,
            child: const Text(PartnerMessages.pagbankSignupConnect),
          ),
        ),
      ],
    );
  }
}

class _Activation extends StatelessWidget {
  const _Activation({
    required this.accountId,
    required this.busy,
    required this.onConnect,
  });

  final String? accountId;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.pagbankSignupActivation,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(PartnerMessages.pagbankSignupActivationApp),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupActivationDocs),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupActivationConnect),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupStays),
        if (accountId != null) ...[
          const SizedBox(height: 8),
          Text(accountId!),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: PartnerKeys.pagbankSignupConnect,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? null : onConnect,
            child: const Text(PartnerMessages.pagbankSignupConnect),
          ),
        ),
      ],
    );
  }
}

class _Exists extends StatelessWidget {
  const _Exists({required this.busy, required this.onConnect});

  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(PartnerMessages.pagbankSignupExists),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: PartnerKeys.pagbankSignupConnect,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? null : onConnect,
            child: const Text(PartnerMessages.pagbankSignupConnect),
          ),
        ),
      ],
    );
  }
}

enum _SignupPhase { form, manual, activation, exists }

String pagbankSignupMessage(String code) {
  return switch (code) {
    'documento' => 'Confira o CPF ou o CNPJ.',
    'cpf_responsavel' => 'Confira o CPF de quem responde pela empresa.',
    'razao' => 'Confira a razão social.',
    'endereco' => 'Confira o endereço. A UF tem duas letras e o CEP, 8 dígitos.',
    'responsavel' => 'Confira o nome de quem responde pela conta.',
    'nascimento' => 'Quem responde pela conta precisa ter 18 anos ou mais.',
    'celular' => 'Informe um celular com DDD.',
    'email' => 'Confira o e-mail.',
    'categoria' => 'Escolha a categoria do negócio.',
    'termos' => 'Aceite os termos do PagBank para continuar.',
    'api_indisponivel' =>
      'O cadastro pela PagBank ainda não está liberado. Crie a conta na página oficial.',
    'conta_email' =>
      'A PagBank pediu para concluir a conta pelo e-mail informado.',
    'pagbank_unavailable' || 'pagbank_resposta' || 'pagbank_connect' =>
      'A PagBank não concluiu o cadastro. Tente de novo em instantes.',
    'ip' => 'Não foi possível registrar o aceite dos termos.',
    'connect' => 'Não foi possível abrir o PagBank Connect.',
    _ => 'Não foi possível cadastrar a conta agora.',
  };
}
