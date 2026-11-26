import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_signup_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Conta PagBank da casa. Sem conta, duas escolhas. O formulário só entra
/// no caminho de criar conta quando a API de Cadastro está liberada.
class VenuePagbankSignupCard extends ConsumerStatefulWidget {
  const VenuePagbankSignupCard({
    super.key,
    required this.venueId,
    this.onOpen,
    this.today,
    this.receivesPayments = false,
    this.inReview = false,
  });

  final String venueId;
  final void Function(Uri uri)? onOpen;
  final DateTime Function()? today;
  final bool receivesPayments;
  final bool inReview;

  @override
  ConsumerState<VenuePagbankSignupCard> createState() =>
      _VenuePagbankSignupCardState();
}

class _VenuePagbankSignupCardState
    extends ConsumerState<VenuePagbankSignupCard> {
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
  var _step = 0;
  var _phase = _SignupPhase.choices;
  PagbankSignupRow? _row;
  String? _error;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VenuePagbankSignupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.receivesPayments != widget.receivesPayments ||
        oldWidget.inReview != widget.inReview;
    if (!changed || _loading) return;
    if (_phase == _SignupPhase.choices ||
        _phase == _SignupPhase.connected ||
        _phase == _SignupPhase.review) {
      _applyRow(_row);
    }
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
        _applyRow(null);
      });
    }
  }

  void _applyRow(PagbankSignupRow? row) {
    _row = row;
    if (row?.accountId != null && !widget.receivesPayments) {
      _accountId = row!.accountId;
      _phase = _SignupPhase.activation;
      return;
    }
    if (row?.accountStatus == 'exists' && !widget.receivesPayments) {
      _phase = _SignupPhase.exists;
      return;
    }
    if (!_api &&
        row?.accountStatus == 'guided' &&
        !widget.receivesPayments &&
        !widget.inReview) {
      _phase = _SignupPhase.manual;
      return;
    }
    if (widget.receivesPayments) {
      _phase = _SignupPhase.connected;
      return;
    }
    if (widget.inReview) {
      _phase = _SignupPhase.review;
      return;
    }
    _phase = _SignupPhase.choices;
  }

  void _clearSensitive() {
    _document.clear();
    _responsibleCpf.clear();
    _birth.clear();
    _phone.clear();
    _email.clear();
  }

  void _chooseHave() {
    setState(() {
      _error = null;
      _phase = _SignupPhase.connect;
    });
  }

  void _chooseCreate() {
    setState(() {
      _error = null;
      _step = 0;
      _phase = _api ? _SignupPhase.form : _SignupPhase.create;
    });
  }

  void _back() {
    setState(() {
      _error = null;
      if (_phase == _SignupPhase.form && _step > 0) {
        _step -= 1;
        return;
      }
      _step = 0;
      if (widget.receivesPayments) {
        _phase = _SignupPhase.connected;
      } else if (widget.inReview) {
        _phase = _SignupPhase.review;
      } else {
        _phase = _SignupPhase.choices;
      }
    });
  }

  void _continue() {
    final issue = _stepIssue(_step);
    if (issue != null) {
      setState(() => _error = pagbankSignupMessage(issue));
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  String? _stepIssue(int step) {
    return PagbankSignupDraft.stepIssue(
      step: step,
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
  }

  Future<void> _submit() async {
    final issue = _stepIssue(2);
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
    if (!_api) {
      setState(() {
        _phase = _SignupPhase.create;
        _error = pagbankSignupMessage('api_indisponivel');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(pagbankSignupRepositoryProvider);
    try {
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
        } else if (error.code == 'api_indisponivel') {
          _clearSensitive();
          _phase = _SignupPhase.create;
          _error = pagbankSignupMessage(error.code);
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
      (widget.onOpen ?? launchPagbankConnect)(uri);
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
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: PartnerKeys.pagbankSignupError,
              style: TextStyle(color: theme.colorScheme.error, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const Text(PartnerMessages.pagbankSignupLoading)
        else
          switch (_phase) {
            _SignupPhase.choices => _Choices(
              onHave: _busy ? null : _chooseHave,
              onCreate: _busy ? null : _chooseCreate,
            ),
            _SignupPhase.connect => _ConnectScreen(
              busy: _busy,
              onConnect: _connect,
              onBack: _back,
            ),
            _SignupPhase.create || _SignupPhase.manual => _CreateOfficial(
              busy: _busy,
              onOpen: _open,
              onEnter: _chooseHave,
              onBack: _back,
            ),
            _SignupPhase.form => _form(theme),
            _SignupPhase.activation => _Activation(
              accountId: _accountId,
              busy: _busy,
              onConnect: _connect,
            ),
            _SignupPhase.exists => _Exists(busy: _busy, onConnect: _connect),
            _SignupPhase.connected => const _StatusNote(
              noteKey: PartnerKeys.pagbankSignupConnected,
              icon: Icons.check_circle,
              tone: _NoteTone.success,
              title: PartnerMessages.pagbankConnectedTitle,
              body: PartnerMessages.pagbankConnectedBody,
            ),
            _SignupPhase.review => const _StatusNote(
              noteKey: PartnerKeys.pagbankSignupReview,
              icon: Icons.hourglass_top,
              tone: _NoteTone.alert,
              title: PartnerMessages.pagbankReviewTitle,
              body: PartnerMessages.pagbankReviewBody,
            ),
          },
      ],
    );
  }

  Widget _form(ThemeData theme) {
    final last = _step >= 2;
    return Column(
      key: PartnerKeys.pagbankSignupForm,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.pagbankCreateTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.pagbankSignupApiBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 16),
        Semantics(
          key: PartnerKeys.pagbankSignupProgress,
          label: PartnerMessages.pagbankSignupStep(_step + 1),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  PartnerMessages.pagbankSignupStep(_step + 1),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / 3,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_step == 0) ...[
          Row(
            children: [
              Expanded(
                child: _KindButton(
                  buttonKey: PartnerKeys.pagbankSignupCpf,
                  label: 'CPF',
                  selected: _kind == 'cpf',
                  onPressed: _busy ? null : () => setState(() => _kind = 'cpf'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KindButton(
                  buttonKey: PartnerKeys.pagbankSignupCnpj,
                  label: 'CNPJ',
                  selected: _kind == 'cnpj',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _kind = 'cnpj'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(
            PartnerKeys.pagbankSignupDocument,
            _kind == 'cnpj' ? 'CNPJ' : 'CPF',
            _document,
          ),
          if (_kind == 'cnpj')
            _field(
              PartnerKeys.pagbankSignupResponsibleCpf,
              'CPF de quem responde pela empresa',
              _responsibleCpf,
            ),
        ] else if (_step == 1) ...[
          _field(
            PartnerKeys.pagbankSignupCompany,
            _kind == 'cnpj' ? 'Razão social' : 'Nome',
            _company,
          ),
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
            decoration: const InputDecoration(
              labelText: 'Categoria do negócio',
            ),
            items: [
              for (final entry in pagbankBusinessCategoryLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _category = value),
          ),
        ] else ...[
          _field(PartnerKeys.pagbankSignupStreet, 'Rua', _street),
          _field(PartnerKeys.pagbankSignupNumber, 'Número', _number),
          _field(
            PartnerKeys.pagbankSignupComplement,
            'Complemento',
            _complement,
          ),
          _field(PartnerKeys.pagbankSignupLocality, 'Bairro', _locality),
          _field(PartnerKeys.pagbankSignupCity, 'Cidade', _city),
          _field(PartnerKeys.pagbankSignupPostal, 'CEP', _postal),
          _field(PartnerKeys.pagbankSignupRegion, 'UF', _region),
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
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _open(pagbankTermsUrl),
                child: const Text(PartnerMessages.pagbankSignupTermsLink),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _open(pagbankPrivacyUrl),
                child: const Text(PartnerMessages.pagbankSignupPrivacyLink),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _NavButtons(
          busy: _busy,
          nextKey: last
              ? PartnerKeys.pagbankSignupSubmit
              : PartnerKeys.pagbankSignupContinue,
          nextLabel: last
              ? PartnerMessages.pagbankSignupSubmitApi
              : PartnerMessages.pagbankSignupContinue,
          onBack: _back,
          onNext: last ? _submit : _continue,
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

class _Choices extends StatelessWidget {
  const _Choices({required this.onHave, required this.onCreate});

  final VoidCallback? onHave;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.pagbankSignupChoices,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.pagbankChoicesTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        _ChoiceCard(
          cardKey: PartnerKeys.pagbankHaveAccount,
          icon: Icons.account_balance_wallet_outlined,
          title: PartnerMessages.pagbankHaveAccount,
          onTap: onHave,
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          cardKey: PartnerKeys.pagbankNoAccount,
          icon: Icons.add_business_outlined,
          title: PartnerMessages.pagbankNoAccount,
          onTap: onCreate,
        ),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.pagbankChoicesBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.pagbankWithdrawHint,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: title,
      child: Material(
        key: cardKey,
        color: scheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectScreen extends StatelessWidget {
  const _ConnectScreen({
    required this.busy,
    required this.onConnect,
    required this.onBack,
  });

  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.pagbankConnectTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.pagbankConnectBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 16),
        _NavButtons(
          busy: busy,
          nextKey: PartnerKeys.pagbankSignupConnect,
          nextLabel: PartnerMessages.pagbankSignupConnect,
          onBack: onBack,
          onNext: onConnect,
        ),
      ],
    );
  }
}

class _CreateOfficial extends StatelessWidget {
  const _CreateOfficial({
    required this.busy,
    required this.onOpen,
    required this.onEnter,
    required this.onBack,
  });

  final bool busy;
  final void Function(String url) onOpen;
  final VoidCallback onEnter;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.pagbankSignupManual,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.pagbankCreateTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.pagbankCreateManualBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 12),
        const Text(PartnerMessages.pagbankSignupManualStepAccount),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupManualStepConnect),
        const SizedBox(height: 8),
        const Text(PartnerMessages.pagbankSignupStays),
        const SizedBox(height: 16),
        FilledButton(
          key: PartnerKeys.pagbankSignupOfficial,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : () => onOpen(pagbankOfficialSignupUrl),
          child: const Text(PartnerMessages.pagbankSignupOpenOfficial),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: PartnerKeys.pagbankSignupEnter,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : onEnter,
          child: const Text(PartnerMessages.pagbankConnectTitle),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: PartnerKeys.pagbankSignupBack,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : onBack,
          child: const Text(PartnerMessages.pagbankSignupBack),
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
        if (accountId != null) ...[const SizedBox(height: 8), Text(accountId!)],
        const SizedBox(height: 12),
        FilledButton(
          key: PartnerKeys.pagbankSignupConnect,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : onConnect,
          child: const Text(PartnerMessages.pagbankSignupConnect),
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
        FilledButton(
          key: PartnerKeys.pagbankSignupConnect,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : onConnect,
          child: const Text(PartnerMessages.pagbankSignupConnect),
        ),
      ],
    );
  }
}

enum _NoteTone { success, alert }

class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.noteKey,
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final Key noteKey;
  final IconData icon;
  final _NoteTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    final background = tone == _NoteTone.success
        ? status.successContainer
        : status.alertContainer;
    final foreground = tone == _NoteTone.success
        ? status.onSuccessContainer
        : status.onAlertContainer;
    final mark = tone == _NoteTone.success ? status.success : status.alert;
    return Semantics(
      label: '$title. $body',
      child: Material(
        key: noteKey,
        color: background,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: mark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.buttonKey,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
    );
    final child = Text(label);
    if (selected) {
      return FilledButton(
        key: buttonKey,
        style: style,
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      key: buttonKey,
      style: style,
      onPressed: onPressed,
      child: child,
    );
  }
}

class _NavButtons extends StatelessWidget {
  const _NavButtons({
    required this.busy,
    required this.nextKey,
    required this.nextLabel,
    required this.onBack,
    required this.onNext,
  });

  final bool busy;
  final Key nextKey;
  final String nextLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: nextKey,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: busy ? null : onNext,
          child: Text(nextLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: PartnerKeys.pagbankSignupBack,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: busy ? null : onBack,
          child: const Text(PartnerMessages.pagbankSignupBack),
        ),
      ],
    );
  }
}

enum _SignupPhase {
  choices,
  connect,
  create,
  form,
  manual,
  activation,
  exists,
  connected,
  review,
}

String pagbankSignupMessage(String code) {
  return switch (code) {
    'documento' => 'Confira o CPF ou o CNPJ.',
    'cpf_responsavel' => 'Confira o CPF de quem responde pela empresa.',
    'razao' => 'Confira o nome ou a razão social.',
    'endereco' =>
      'Confira o endereço. A UF tem duas letras e o CEP, 8 dígitos.',
    'responsavel' => 'Confira o nome de quem responde pela conta.',
    'nascimento' => 'Quem responde pela conta precisa ter 18 anos ou mais.',
    'celular' => 'Informe um celular com DDD.',
    'email' => 'Confira o e-mail.',
    'categoria' => 'Escolha a categoria do negócio.',
    'termos' => 'Aceite os termos do PagBank para continuar.',
    'api_indisponivel' => 'O cadastro pela PagBank ainda não está liberado. Crie a conta na página oficial.',
    'conta_email' =>
      'A PagBank pediu para concluir a conta pelo e-mail informado.',
    'pagbank_unavailable' || 'pagbank_resposta' || 'pagbank_connect' =>
      'A PagBank não concluiu o cadastro. Tente de novo em instantes.',
    'ip' => 'Não foi possível registrar o aceite dos termos.',
    'connect' => 'Não foi possível abrir o PagBank Connect.',
    _ => 'Não foi possível cadastrar a conta agora.',
  };
}
