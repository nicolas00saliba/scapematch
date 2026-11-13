import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class VenueClaimOffer extends StatelessWidget {
  const VenueClaimOffer({
    super.key,
    required this.venue,
    required this.onClaim,
  });

  final ClaimableVenue venue;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: PartnerKeys.venueClaimOffer,
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              PartnerMessages.claimOfferTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              venue.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (venue.neighborhood.isNotEmpty) Text(venue.neighborhood),
            const SizedBox(height: 8),
            Text(PartnerMessages.claimOfferBody),
            const SizedBox(height: 12),
            FilledButton(
              key: PartnerKeys.venueClaim,
              onPressed: onClaim,
              child: const Text(PartnerMessages.claimOfferButton),
            ),
          ],
        ),
      ),
    );
  }
}

class VenueClaimDesk extends StatefulWidget {
  const VenueClaimDesk({
    super.key,
    required this.venue,
    required this.onSend,
    required this.onConfirm,
    required this.onProvision,
    this.onOpenHouse,
  });

  final ClaimableVenue venue;
  final Future<ClaimDispatch> Function() onSend;
  final Future<bool> Function(String code) onConfirm;
  final Future<String?> Function() onProvision;
  final VoidCallback? onOpenHouse;

  @override
  State<VenueClaimDesk> createState() => _VenueClaimDeskState();
}

class _VenueClaimDeskState extends State<VenueClaimDesk> {
  final _code = TextEditingController();
  String? _message;
  String? _error;
  var _busy = false;
  var _linked = false;
  var _sent = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSend();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = result.sent;
        _message = result.manual
            ? PartnerMessages.claimManualSent
            : result.sent
            ? 'Enviamos o código${result.hint.isEmpty ? '' : ' para ${result.hint}'}.'
            : result.status == 'rate'
            ? PartnerMessages.claimRate
            : 'Não foi possível enviar o código.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Não foi possível enviar o código.';
      });
    }
  }

  Future<void> _confirm() async {
    if (!claimCodeLooksValid(_code.text)) {
      setState(() => _error = PartnerMessages.claimMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.onConfirm(_code.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _linked = ok;
        _error = ok ? null : PartnerMessages.claimMismatch;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = PartnerMessages.claimMismatch;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.venue.path == VenueClaimPath.manual && !_sent) {
      return _panel(
        children: [
          Text(widget.venue.name),
          const SizedBox(height: 8),
          const Text(PartnerMessages.claimManualSent),
          const SizedBox(height: 12),
          FilledButton(
            key: PartnerKeys.venueClaimSend,
            onPressed: _busy ? null : _send,
            child: const Text('Pedir aprovação'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, key: PartnerKeys.venueClaimSent),
          ],
        ],
      );
    }
    if (_linked) {
      return VenueFinanceStep(
        onProvision: widget.onProvision,
        onOpenHouse: widget.onOpenHouse,
      );
    }
    return _panel(
      children: [
        Text(
          PartnerMessages.claimCodeTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(widget.venue.name),
        const SizedBox(height: 8),
        const Text(PartnerMessages.claimCodeBody),
        const SizedBox(height: 12),
        FilledButton(
          key: PartnerKeys.venueClaimSend,
          onPressed: _busy ? null : _send,
          child: const Text(PartnerMessages.claimSendCode),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, key: PartnerKeys.venueClaimSent),
        ],
        const SizedBox(height: 12),
        TextField(
          key: PartnerKeys.venueClaimCode,
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: PartnerMessages.claimCodeHint,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: PartnerKeys.venueClaimConfirm,
          onPressed: _busy ? null : _confirm,
          child: const Text(PartnerMessages.claimConfirmCode),
        ),
        if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
      ],
    );
  }

  Widget _panel({required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: children,
    );
  }
}

class VenueFinanceStep extends StatefulWidget {
  const VenueFinanceStep({
    super.key,
    required this.onProvision,
    this.onOpenHouse,
  });

  final Future<String?> Function() onProvision;
  final VoidCallback? onOpenHouse;

  @override
  State<VenueFinanceStep> createState() => _VenueFinanceStepState();
}

class _VenueFinanceStepState extends State<VenueFinanceStep> {
  String? _message;
  var _busy = false;

  Future<void> _provision() async {
    setState(() => _busy = true);
    final error = await widget.onProvision();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? PartnerMessages.claimProvisionDone;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PartnerKeys.venueClaimFinance,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text(
          PartnerMessages.claimLinked,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(PartnerMessages.claimFinanceBody),
        const SizedBox(height: 8),
        const Text(PartnerMessages.claimBankHint),
        const SizedBox(height: 16),
        FilledButton(
          key: PartnerKeys.venueClaimProvision,
          onPressed: _busy ? null : _provision,
          child: const Text(PartnerMessages.claimProvision),
        ),
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
        if (widget.onOpenHouse != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onOpenHouse,
            child: const Text('Abrir a casa'),
          ),
        ],
      ],
    );
  }
}
