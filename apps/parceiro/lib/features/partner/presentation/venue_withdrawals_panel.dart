import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
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
  var _loading = true;
  var _editingBank = false;
  var _busy = false;
  String? _error;
  String _destination = 'pix';
  String _pixType = 'CNPJ';
  String _operation = 'PIX';
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
  var _frequency = 'daily';

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
    final snapshot = await ref
        .read(venueWithdrawalRepositoryProvider)
        .load(widget.venueId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _apply(snapshot);
    });
  }

  void _apply(VenuePayoutSnapshot snapshot) {
    _snapshot = snapshot;
    _auto = snapshot.schedule.enabled;
    _frequency = snapshot.schedule.frequency;
    _weekday = snapshot.schedule.weekday ?? _weekday;
    if (snapshot.schedule.minAmountCents > 0) {
      _minimum.text = _reais(snapshot.schedule.minAmountCents);
    }
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
      operationType: _operation,
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
      frequency: _frequency,
      weekday: _frequency == 'weekly' ? _weekday : null,
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
    if (_loading) return const LinearProgressIndicator();
    if (snapshot == null || !snapshot.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final staff = snapshot.role == 'staff' || !snapshot.canWithdraw;
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.withdrawalsTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(PartnerMessages.withdrawalsBody),
        const SizedBox(height: 16),
        if (staff)
          Text(PartnerMessages.withdrawalStaff)
        else ...[
          _BalanceCard(snapshot: snapshot),
          if (snapshot.withdrawalsBlocked) ...[
            const SizedBox(height: 12),
            Text(PartnerMessages.withdrawalBlocked),
          ],
          const SizedBox(height: 16),
          Text(
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
          const SizedBox(height: 16),
          TextField(
            key: PartnerKeys.withdrawalAmount,
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: PartnerMessages.withdrawalAmount,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: PartnerKeys.withdrawalSubmit,
              onPressed: _busy || snapshot.withdrawalsBlocked
                  ? null
                  : _withdraw,
              child: const Text(PartnerMessages.withdrawalSubmit),
            ),
          ),
          const SizedBox(height: 20),
          _BankSection(
            snapshot: snapshot,
            editing: _editingBank,
            destination: _destination,
            pixType: _pixType,
            operation: _operation,
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
            onOperation: (value) => setState(() => _operation = value),
            onSave: _saveBank,
          ),
          const SizedBox(height: 20),
          _ScheduleSection(
            auto: _auto,
            frequency: _frequency,
            weekday: _weekday ?? 1,
            minimum: _minimum,
            busy: _busy,
            onAuto: (value) => setState(() => _auto = value),
            onFrequency: (value) => setState(() => _frequency = value),
            onWeekday: (value) => setState(() => _weekday = value),
            onSave: _saveSchedule,
          ),
          const SizedBox(height: 20),
          Text(
            PartnerMessages.withdrawalHistory,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (snapshot.withdrawals.isEmpty)
            const Text(PartnerMessages.withdrawalEmpty)
          else
            for (final item in snapshot.withdrawals)
              _WithdrawalTile(item: item),
        ],
        if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.snapshot});

  final VenuePayoutSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PartnerMessages.availableLabel),
            const SizedBox(height: 4),
            Text(
              formatPrice(snapshot.availableCents),
              key: PartnerKeys.withdrawalBalance,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (snapshot.pendingCents > 0)
              Text('Pendente ${formatPrice(snapshot.pendingCents)}'),
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
    required this.operation,
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
    required this.onOperation,
    required this.onSave,
  });

  final VenuePayoutSnapshot snapshot;
  final bool editing;
  final String destination;
  final String pixType;
  final String operation;
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
  final ValueChanged<String> onOperation;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bank = snapshot.bank;
    return Column(
      key: PartnerKeys.withdrawalBank,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
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
            DropdownButtonFormField<String>(
              initialValue: operation,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'PIX', child: Text('Pix')),
                DropdownMenuItem(value: 'TED', child: Text('TED')),
              ],
              onChanged: (value) {
                if (value != null) onOperation(value);
              },
            ),
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
    return 'Banco ${bank.bankCode ?? ''} · ag ${bank.agency ?? ''} · ${bank.accountMasked ?? ''} · ${bank.operationType}';
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({
    required this.auto,
    required this.frequency,
    required this.weekday,
    required this.minimum,
    required this.busy,
    required this.onAuto,
    required this.onFrequency,
    required this.onWeekday,
    required this.onSave,
  });

  final bool auto;
  final String frequency;
  final int weekday;
  final TextEditingController minimum;
  final bool busy;
  final ValueChanged<bool> onAuto;
  final ValueChanged<String> onFrequency;
  final ValueChanged<int> onWeekday;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.withdrawalAuto,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.withdrawalAuto,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(PartnerMessages.withdrawalAutoBody),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(PartnerMessages.withdrawalAuto),
          value: auto,
          onChanged: busy ? null : onAuto,
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text(PartnerMessages.withdrawalDaily),
              selected: frequency == 'daily',
              onSelected: (_) => onFrequency('daily'),
            ),
            ChoiceChip(
              label: const Text(PartnerMessages.withdrawalWeekly),
              selected: frequency == 'weekly',
              onSelected: (_) => onFrequency('weekly'),
            ),
          ],
        ),
        if (frequency == 'weekly')
          DropdownButtonFormField<int>(
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
            onChanged: (value) {
              if (value != null) onWeekday(value);
            },
          ),
        TextField(
          controller: minimum,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: PartnerMessages.withdrawalMinimum,
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
  const _WithdrawalTile({required this.item});

  final VenueWithdrawal item;

  @override
  Widget build(BuildContext context) {
    final receipt = item.receiptUrl;
    final secure = receipt != null && receipt.startsWith('https://');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatPrice(item.amountCents)} · ${_status(item.status)} · ${_source(item.source)}',
          ),
          Text(_stamp(item.createdAt)),
          if (secure)
            TextButton(
              key: PartnerKeys.withdrawalReceipt,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => launchExternalUrl(Uri.parse(receipt)),
              child: const Text(PartnerMessages.withdrawalReceipt),
            ),
        ],
      ),
    );
  }

  String _status(String status) {
    return switch (status) {
      'done' => PartnerMessages.withdrawalDone,
      'failed' => PartnerMessages.withdrawalFailed,
      'cancelled' => PartnerMessages.withdrawalCancelled,
      _ => PartnerMessages.withdrawalPending,
    };
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

String _reais(int cents) {
  final whole = cents ~/ 100;
  final fraction = (cents % 100).toString().padLeft(2, '0');
  return '$whole,$fraction';
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
