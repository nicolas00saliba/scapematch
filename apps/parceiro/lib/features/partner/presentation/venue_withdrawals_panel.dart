import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_documents_card.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Saldo da subconta, conta de saque e histórico.
///
/// Some quando a flag está desligada ou a função ainda não existe.
class VenueWithdrawalsPanel extends ConsumerStatefulWidget {
  const VenueWithdrawalsPanel({super.key, required this.venueId, this.email});

  final String venueId;

  /// E-mail usado na reautenticação. Sem ele, a sessão da casa entra.
  final String? email;

  @override
  ConsumerState<VenueWithdrawalsPanel> createState() =>
      _VenueWithdrawalsPanelState();
}

class _VenueWithdrawalsPanelState extends ConsumerState<VenueWithdrawalsPanel> {
  VenuePayoutSnapshot? _snapshot;
  VenueDocumentsView _documents = VenueDocumentsView.hidden;
  var _loading = true;
  var _loadFailed = false;
  var _editingBank = false;
  var _busy = false;
  String? _error;
  String _destination = 'pix';
  String _pixType = 'CNPJ';
  int? _weekday = 1;

  final _amount = TextEditingController();
  final _owner = TextEditingController();
  final _document = TextEditingController();
  final _pix = TextEditingController();
  final _bankCode = TextEditingController();
  final _agency = TextEditingController();
  final _account = TextEditingController();
  final _digit = TextEditingController();
  final _minimum = TextEditingController(text: '50,00');
  var _auto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _owner.dispose();
    _document.dispose();
    _pix.dispose();
    _bankCode.dispose();
    _agency.dispose();
    _account.dispose();
    _digit.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final snapshot = await ref
          .read(venueWithdrawalRepositoryProvider)
          .load(widget.venueId);
      final documents = await _readDocuments();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = false;
        _apply(snapshot);
        _documents = documents;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<VenueDocumentsView> _readDocuments() async {
    try {
      return await ref
          .read(venueDocumentsRepositoryProvider)
          .load(widget.venueId);
    } on VenueDocumentsFailure catch (error) {
      if (error.code == 'not owner') return VenueDocumentsView.hidden;
      return VenueDocumentsView.unavailable;
    } on Object {
      return VenueDocumentsView.unavailable;
    }
  }

  Future<void> _refreshDocuments() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final documents = await _readDocuments();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _documents = documents;
      });
    } on VenueDocumentsFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = venueDocumentFailureMessage(error.code);
      });
    }
  }

  Future<void> _uploadDocument(VenueDocumentItem item) async {
    final file = await ref.read(venueDocumentPickerProvider).pick();
    if (file == null || !mounted) return;
    if (!await _guard()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final documents = await ref
          .read(venueDocumentsRepositoryProvider)
          .upload(
            venueId: widget.venueId,
            documentId: item.id,
            bytes: file.bytes,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _documents = documents;
      });
    } on VenueDocumentsFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = venueDocumentFailureMessage(error.code);
      });
    }
  }

  void _apply(VenuePayoutSnapshot snapshot) {
    _snapshot = snapshot;
    _auto = snapshot.schedule.enabled;
    _weekday = snapshot.schedule.weekday ?? _weekday ?? 1;
    if (snapshot.schedule.minAmountCents > 0) {
      _minimum.text = _reais(snapshot.schedule.minAmountCents);
    }
  }

  bool _canRetry(VenuePayoutSnapshot snapshot, VenueWithdrawal item) {
    return item.status == 'failed' &&
        snapshot.canWithdraw &&
        !snapshot.withdrawalsBlocked &&
        item.amountCents > 0 &&
        item.amountCents <= snapshot.availableCents;
  }

  Future<void> _withdraw() async {
    final snapshot = _snapshot;
    final cents = parseWithdrawalAmount(_amount.text);
    if (cents == null) {
      setState(() => _error = PartnerMessages.withdrawalAmountInvalid);
      return;
    }
    if (snapshot != null && cents > snapshot.availableCents) {
      setState(() => _error = payoutErrorMessage('saldo'));
      return;
    }
    if (!await _guard()) return;
    await _run(
      () => ref
          .read(venueWithdrawalRepositoryProvider)
          .withdraw(widget.venueId, cents),
    );
  }

  Future<void> _saveBank() async {
    if (!await _guard()) return;
    final draft = VenueBankDraft(
      destination: _destination,
      ownerName: _owner.text.trim(),
      ownerDocument: _document.text.trim(),
      operationType: 'PIX',
      pixKey: _pix.text.trim(),
      pixKeyType: _pixType,
      bankCode: _bankCode.text.trim(),
      agency: _agency.text.trim(),
      accountNumber: _account.text.trim(),
      accountDigit: _digit.text.trim(),
    );
    await _run(
      () => ref
          .read(venueWithdrawalRepositoryProvider)
          .saveBank(widget.venueId, draft),
    );
    if (!mounted || _error != null) return;
    setState(() => _editingBank = false);
  }

  Future<void> _saveSchedule() async {
    final minimum = parseWithdrawalAmount(_minimum.text) ?? 0;
    if (!await _guard()) return;
    final schedule = VenuePayoutSchedule(
      enabled: _auto,
      frequency: 'weekly',
      weekday: _weekday ?? 1,
      minAmountCents: minimum,
    );
    await _run(
      () => ref
          .read(venueWithdrawalRepositoryProvider)
          .saveSchedule(widget.venueId, schedule),
    );
  }

  Future<bool> _guard() async {
    final repo = ref.read(venueWithdrawalRepositoryProvider);
    final email = widget.email ?? ref.read(partnerSessionProvider)?.email ?? '';
    final totp = await repo.needsTotp();
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ReauthDialog(
        needsTotp: totp,
        onSubmit: (password, code) =>
            repo.reauthenticate(email: email, password: password, totp: code),
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<VenuePayoutSnapshot> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _apply(snapshot);
      });
    } on PayoutFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = payoutErrorMessage(error.code);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (_loading) return const _WithdrawalsLoading();
    if (_loadFailed) return _WithdrawalsLoadError(onRetry: _load);
    if (snapshot == null || !snapshot.enabled) {
      return const _WithdrawalsUnavailable();
    }
    final theme = Theme.of(context);
    final staff = snapshot.role == 'staff' || !snapshot.canWithdraw;
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          PartnerMessages.withdrawalsTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(PartnerMessages.withdrawalsBody),
        const SizedBox(height: 16),
        if (!staff) ...[
          _Heading(
            PartnerMessages.withdrawalBalanceSection,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _BalanceCard(snapshot: snapshot),
          if (snapshot.withdrawalsBlocked) ...[
            const SizedBox(height: 12),
            Text(
              PartnerMessages.withdrawalBlocked,
              style: TextStyle(
                color:
                    Theme.of(context).extension<ScapeStatusColors>()?.alert ??
                    theme.colorScheme.tertiary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          VenueDocumentsCard(
            view: _documents,
            busy: _busy,
            onOpen: launchExternalUrl,
            onUpload: _uploadDocument,
            onRefresh: _refreshDocuments,
          ),
          if (_documents.visible) const SizedBox(height: 16),
          _ReceivablesCard(snapshot: snapshot),
          const SizedBox(height: 16),
          _PayoutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: PartnerKeys.withdrawalAmount,
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [_ReaisMaskFormatter()],
                  decoration: const InputDecoration(
                    labelText: PartnerMessages.withdrawalAmount,
                    prefixText: r'R$ ',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: PartnerKeys.withdrawalAll,
                    style: _tapTarget(),
                    onPressed: _busy || snapshot.availableCents <= 0
                        ? null
                        : () => _amount.text = _reais(snapshot.availableCents),
                    child: const Text(PartnerMessages.withdrawalAll),
                  ),
                ),
                FilledButton(
                  key: PartnerKeys.withdrawalSubmit,
                  onPressed:
                      _busy ||
                          snapshot.withdrawalsBlocked ||
                          _documents.blocksWithdraw
                      ? null
                      : _withdraw,
                  child: const Text(PartnerMessages.withdrawalSubmit),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _HistoryCard(
            snapshot: snapshot,
            canRetry: _canRetry,
            onRetry: (item) {
              _amount.text = _reais(item.amountCents);
              _withdraw();
            },
          ),
          const SizedBox(height: 24),
          _PayoutCard(
            child: _BankSection(
              snapshot: snapshot,
              editing: _editingBank,
              destination: _destination,
              pixType: _pixType,
              owner: _owner,
              document: _document,
              pix: _pix,
              bankCode: _bankCode,
              agency: _agency,
              account: _account,
              digit: _digit,
              busy: _busy,
              onEdit: () => setState(() => _editingBank = true),
              onDestination: (value) => setState(() => _destination = value),
              onPixType: (value) => setState(() => _pixType = value),
              onSave: _saveBank,
            ),
          ),
          const SizedBox(height: 16),
          _PayoutCard(
            child: _ScheduleSection(
              auto: _auto,
              weekday: _weekday ?? 1,
              minimum: _minimum,
              busy: _busy,
              onAuto: (value) => setState(() => _auto = value),
              onWeekday: (value) => setState(() => _weekday = value),
              onSave: _saveSchedule,
            ),
          ),
          const SizedBox(height: 24),
        ] else ...[
          VenueDocumentsCard(
            view: _documents,
            busy: _busy,
            onOpen: launchExternalUrl,
            onUpload: _uploadDocument,
            onRefresh: _refreshDocuments,
          ),
          if (_documents.visible) const SizedBox(height: 16),
          const _PayoutCard(child: Text(PartnerMessages.withdrawalStaff)),
        ],
        const SizedBox(height: 24),
        const _HowItWorks(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_error!)),
        ],
      ],
    );
  }
}

class _WithdrawalsLoading extends StatelessWidget {
  const _WithdrawalsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(child: LinearProgressIndicator()),
          SizedBox(height: 12),
          Text(PartnerMessages.withdrawalsLoading),
        ],
      ),
    );
  }
}

class _WithdrawalsLoadError extends StatelessWidget {
  const _WithdrawalsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          PartnerMessages.withdrawalsTitle,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(PartnerMessages.withdrawalsLoadError),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: PartnerKeys.withdrawalsReload,
            onPressed: onRetry,
            child: const Text(PartnerMessages.retry),
          ),
        ),
      ],
    );
  }
}

class _WithdrawalsUnavailable extends StatelessWidget {
  const _WithdrawalsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          PartnerMessages.withdrawalsTitle,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(PartnerMessages.withdrawalsUnavailable),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(header: true, child: Text(text, style: style));
  }
}

class _ReceivablesCard extends StatelessWidget {
  const _ReceivablesCard({required this.snapshot});

  final VenuePayoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PayoutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            PartnerMessages.receivableLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (snapshot.receivables.isEmpty)
            const Text(PartnerMessages.receivableEmpty)
          else
            for (final item in snapshot.receivables)
              Text(
                '${formatPrice(item.cents)} · ${_day(item.creditDate)} · ${item.description}',
              ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.snapshot,
    required this.canRetry,
    required this.onRetry,
  });

  final VenuePayoutSnapshot snapshot;
  final bool Function(VenuePayoutSnapshot snapshot, VenueWithdrawal item)
  canRetry;
  final ValueChanged<VenueWithdrawal> onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PayoutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            PartnerMessages.withdrawalHistory,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (snapshot.withdrawals.isEmpty)
            const Text(PartnerMessages.withdrawalEmpty)
          else
            for (var i = 0; i < snapshot.withdrawals.length; i++) ...[
              _WithdrawalTile(
                item: snapshot.withdrawals[i],
                canRetry: canRetry(snapshot, snapshot.withdrawals[i]),
                onRetry: () => onRetry(snapshot.withdrawals[i]),
              ),
              if (i != snapshot.withdrawals.length - 1)
                Divider(height: 24, color: theme.colorScheme.outlineVariant),
            ],
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PayoutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            PartnerMessages.withdrawalHowTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(PartnerMessages.withdrawalPixNotice),
          const SizedBox(height: 8),
          const Text(PartnerMessages.withdrawalHowCard),
          const SizedBox(height: 8),
          const Text(PartnerMessages.withdrawalBlocked),
          const SizedBox(height: 8),
          const Text(PartnerMessages.withdrawalHowDocs),
        ],
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

ButtonStyle _tapTarget() {
  return TextButton.styleFrom(
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    tapTargetSize: MaterialTapTargetSize.padded,
    alignment: Alignment.centerLeft,
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.snapshot});

  final VenuePayoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expected = snapshot.receivables.fold<int>(
      0,
      (sum, item) => sum + item.cents,
    );
    final tiles = <Widget>[
      _BalanceTile(
        label: PartnerMessages.availableLabel,
        amount: formatPrice(snapshot.availableCents),
        amountKey: PartnerKeys.withdrawalBalance,
        emphasized: true,
      ),
      if (snapshot.pendingCents > 0)
        _BalanceTile(
          label: 'Pendente',
          amount: formatPrice(snapshot.pendingCents),
          amountKey: PartnerKeys.withdrawalPendingBalance,
        ),
      _BalanceTile(
        label: PartnerMessages.receivableLabel,
        amount: formatPrice(expected),
        amountKey: PartnerKeys.withdrawalExpected,
      ),
    ];
    final wide = isScapeDesktop(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < tiles.length; index++) ...[
                    if (index > 0) const SizedBox(width: 16),
                    Expanded(child: tiles[index]),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < tiles.length; index++) ...[
                    if (index > 0) const SizedBox(height: 12),
                    tiles[index],
                  ],
                ],
              ),
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.amount,
    required this.amountKey,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final Key amountKey;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label. $amount',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(
              amount,
              key: amountKey,
              style:
                  (emphasized
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankSection extends StatelessWidget {
  const _BankSection({
    required this.snapshot,
    required this.editing,
    required this.destination,
    required this.pixType,
    required this.owner,
    required this.document,
    required this.pix,
    required this.bankCode,
    required this.agency,
    required this.account,
    required this.digit,
    required this.busy,
    required this.onEdit,
    required this.onDestination,
    required this.onPixType,
    required this.onSave,
  });

  final VenuePayoutSnapshot snapshot;
  final bool editing;
  final String destination;
  final String pixType;
  final TextEditingController owner;
  final TextEditingController document;
  final TextEditingController pix;
  final TextEditingController bankCode;
  final TextEditingController agency;
  final TextEditingController account;
  final TextEditingController digit;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<String> onDestination;
  final ValueChanged<String> onPixType;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bank = snapshot.bank;
    return Column(
      key: PartnerKeys.withdrawalBank,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          PartnerMessages.withdrawalBank,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (bank == null)
          const Text(PartnerMessages.withdrawalNoBank)
        else
          Text(_bankLine(bank)),
        if (!editing)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: _tapTarget(),
              onPressed: onEdit,
              child: Text(
                bank == null
                    ? PartnerMessages.withdrawalSaveBank
                    : PartnerMessages.withdrawalChangeBank,
              ),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text(PartnerMessages.withdrawalPix),
                selected: destination == 'pix',
                onSelected: (_) => onDestination('pix'),
              ),
              ChoiceChip(
                label: const Text(PartnerMessages.withdrawalBankAccount),
                selected: destination == 'bank',
                onSelected: (_) => onDestination('bank'),
              ),
            ],
          ),
          TextField(
            controller: owner,
            decoration: const InputDecoration(
              labelText: PartnerMessages.withdrawalOwner,
            ),
          ),
          TextField(
            key: PartnerKeys.withdrawalDocument,
            controller: document,
            decoration: const InputDecoration(
              labelText: PartnerMessages.withdrawalDocument,
            ),
          ),
          if (destination == 'pix') ...[
            DropdownButtonFormField<String>(
              initialValue: pixType,
              decoration: const InputDecoration(labelText: 'Tipo da chave'),
              items: const [
                DropdownMenuItem(value: 'CPF', child: Text('CPF')),
                DropdownMenuItem(value: 'CNPJ', child: Text('CNPJ')),
                DropdownMenuItem(value: 'EMAIL', child: Text('E-mail')),
                DropdownMenuItem(value: 'PHONE', child: Text('Celular')),
                DropdownMenuItem(value: 'EVP', child: Text('Aleatória')),
              ],
              onChanged: (value) {
                if (value != null) onPixType(value);
              },
            ),
            TextField(
              key: PartnerKeys.withdrawalPix,
              controller: pix,
              decoration: const InputDecoration(
                labelText: PartnerMessages.withdrawalPix,
              ),
            ),
          ] else ...[
            TextField(
              controller: bankCode,
              decoration: const InputDecoration(labelText: 'Banco'),
            ),
            TextField(
              controller: agency,
              decoration: const InputDecoration(labelText: 'Agência'),
            ),
            TextField(
              controller: account,
              decoration: const InputDecoration(labelText: 'Conta'),
            ),
            TextField(
              controller: digit,
              decoration: const InputDecoration(labelText: 'Dígito'),
            ),
            const Text(PartnerMessages.withdrawalBankPix),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: PartnerKeys.withdrawalSaveBank,
              onPressed: busy ? null : onSave,
              child: const Text(PartnerMessages.withdrawalSaveBank),
            ),
          ),
        ],
      ],
    );
  }

  String _bankLine(VenueBankSummary bank) {
    if (bank.destination == 'pix') {
      return 'Pix ${bank.pixKeyType ?? ''} · ${bank.pixKeyMasked ?? ''} · ${bank.ownerName}';
    }
    return 'Pix · banco ${bank.bankCode ?? ''} · ag ${bank.agency ?? ''} · ${bank.accountMasked ?? ''}';
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.auto,
    required this.weekday,
    required this.minimum,
    required this.busy,
    required this.onAuto,
    required this.onWeekday,
    required this.onSave,
  });

  final bool auto;
  final int weekday;
  final TextEditingController minimum;
  final bool busy;
  final ValueChanged<bool> onAuto;
  final ValueChanged<int> onWeekday;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.withdrawalAuto,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          PartnerMessages.withdrawalAuto,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(PartnerMessages.withdrawalAutoBody),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(PartnerMessages.withdrawalAutoSwitch),
          value: auto,
          onChanged: busy ? null : onAuto,
        ),
        Opacity(
          opacity: auto ? 1 : 0.45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(PartnerMessages.withdrawalWeekly),
              DropdownButtonFormField<int>(
                key: PartnerKeys.withdrawalWeekday,
                initialValue: weekday,
                decoration: const InputDecoration(labelText: 'Dia'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Domingo')),
                  DropdownMenuItem(value: 1, child: Text('Segunda')),
                  DropdownMenuItem(value: 2, child: Text('Terça')),
                  DropdownMenuItem(value: 3, child: Text('Quarta')),
                  DropdownMenuItem(value: 4, child: Text('Quinta')),
                  DropdownMenuItem(value: 5, child: Text('Sexta')),
                  DropdownMenuItem(value: 6, child: Text('Sábado')),
                ],
                onChanged: auto
                    ? (value) {
                        if (value != null) onWeekday(value);
                      }
                    : null,
              ),
              TextField(
                enabled: auto && !busy,
                controller: minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: PartnerMessages.withdrawalMinimum,
                  prefixText: r'R$ ',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : onSave,
            child: const Text(PartnerMessages.withdrawalSaveSchedule),
          ),
        ),
      ],
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({
    required this.item,
    required this.canRetry,
    required this.onRetry,
  });

  final VenueWithdrawal item;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = item.receiptUrl;
    final secure = receipt != null && receipt.startsWith('https://');
    final failed = item.status == 'failed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${formatPrice(item.amountCents)} · ${_source(item.source)}'),
        const SizedBox(height: 2),
        Text(
          _stamp(item.createdAt),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _StatusChip(status: item.status),
        if (secure)
          TextButton(
            key: PartnerKeys.withdrawalReceipt,
            style: _tapTarget(),
            onPressed: () => launchExternalUrl(Uri.parse(receipt)),
            child: const Text(PartnerMessages.withdrawalReceipt),
          ),
        if (failed) ...[
          const SizedBox(height: 6),
          Text(
            withdrawalFailureMessage(item.failureReason),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (canRetry)
            TextButton(
              key: PartnerKeys.withdrawalRetry,
              style: _tapTarget(),
              onPressed: onRetry,
              child: const Text(PartnerMessages.withdrawalRetry),
            ),
        ],
      ],
    );
  }

  String _source(String source) {
    return source == 'automatic'
        ? PartnerMessages.withdrawalAutomatic
        : PartnerMessages.withdrawalManual;
  }
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.needsTotp, required this.onSubmit});

  final bool needsTotp;
  final Future<String?> Function(String password, String? totp) onSubmit;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _password = TextEditingController();
  final _totp = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      _password.text,
      widget.needsTotp ? _totp.text : null,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(PartnerMessages.withdrawalReauth),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: PartnerKeys.withdrawalPassword,
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: PartnerMessages.withdrawalPassword,
            ),
          ),
          if (widget.needsTotp)
            TextField(
              controller: _totp,
              decoration: const InputDecoration(
                labelText: PartnerMessages.withdrawalTotp,
              ),
            ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: PartnerKeys.withdrawalConfirm,
          onPressed: _busy ? null : _submit,
          child: const Text(PartnerMessages.withdrawalConfirm),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<ScapeStatusColors>();
    final (label, icon, background, foreground) = switch (status) {
      'done' => (
        PartnerMessages.withdrawalDone,
        Icons.check_circle,
        colors?.successContainer ?? const Color(0xFFD7F3E3),
        colors?.onSuccessContainer ?? const Color(0xFF1E7046),
      ),
      'failed' => (
        PartnerMessages.withdrawalFailed,
        Icons.error,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      'cancelled' => (
        PartnerMessages.withdrawalCancelled,
        Icons.cancel,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _ => (
        PartnerMessages.withdrawalPending,
        Icons.schedule,
        colors?.alertContainer ?? const Color(0xFFFFF1D0),
        colors?.onAlertContainer ?? const Color(0xFF8A5A00),
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 18, color: foreground)),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaisMaskFormatter extends TextInputFormatter {
  const _ReaisMaskFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final trimmed = digits.length > 11 ? digits.substring(0, 11) : digits;
    final text = _reais(int.parse(trimmed));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Frase curta do motivo. Código interno vira texto; frase do Asaas passa.
String withdrawalFailureMessage(String? reason) {
  final text = reason?.trim() ?? '';
  if (text.isEmpty || text == 'falhou' || text == 'erro') {
    return 'O Asaas não concluiu este saque.';
  }
  if (text == 'asaas_unavailable') {
    return 'O Asaas não respondeu. Tente de novo em instantes.';
  }
  if (text == 'sem pix') {
    return 'Este banco ou esta chave não aceita Pix. Cadastre uma chave Pix ou uma conta que receba Pix.';
  }
  if (text.startsWith('internal_error')) {
    return 'Não foi possível concluir o saque.';
  }
  final lower = text.toLowerCase();
  if (lower.contains('insufficient')) {
    return 'Saldo insuficiente na subconta.';
  }
  if (lower.contains('not authorized') || lower.contains('não autoriz')) {
    return 'A transferência não foi autorizada.';
  }
  final safe = _safeAsaasPhrase(text);
  if (safe != null) return safe;
  return 'O Asaas não concluiu este saque.';
}

String? _safeAsaasPhrase(String text) {
  if (text.length < 8 || text.length > 80 || !text.contains(' ')) return null;
  final lower = text.toLowerCase();
  const blocked = ['aact_', 'bearer', 'api_key', 'secret', 'token', 'eyj'];
  if (blocked.any(lower.contains)) return null;
  if (text.contains('@') || text.contains('http')) return null;
  if (RegExp(r'\d{11,}').hasMatch(text)) return null;
  return text;
}

String _reais(int cents) {
  final whole = cents ~/ 100;
  final fraction = (cents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return '$grouped,$fraction';
}

String _day(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  final month = int.tryParse(parts[1]) ?? 0;
  final day = int.tryParse(parts[2]) ?? 0;
  if (month < 1 || month > 12 || day < 1) return iso;
  return '$day ${months[month - 1]} ${parts[0]}';
}

String _stamp(DateTime value) {
  final local = value.toLocal();
  return _day(
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}',
  );
}
