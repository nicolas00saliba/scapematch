import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_documents_card.dart';
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
    this.onLoadDocuments,
    this.onUploadDocument,
    this.onOpenUrl,
    this.onPixReady,
  });

  final ClaimableVenue venue;
  final Future<ClaimDispatch> Function() onSend;
  final Future<bool> Function(String code) onConfirm;
  final Future<String?> Function() onProvision;
  final VoidCallback? onOpenHouse;
  final Future<VenueDocumentsView> Function()? onLoadDocuments;
  final Future<VenueDocumentsView?> Function(VenueDocumentItem item)?
  onUploadDocument;
  final void Function(Uri uri)? onOpenUrl;
  final Future<bool> Function()? onPixReady;

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
        onLoadDocuments: widget.onLoadDocuments,
        onUploadDocument: widget.onUploadDocument,
        onOpenUrl: widget.onOpenUrl,
        onPixReady: widget.onPixReady,
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
    this.onLoadDocuments,
    this.onUploadDocument,
    this.onOpenUrl,
    this.onPixReady,
  });

  final Future<String?> Function() onProvision;
  final VoidCallback? onOpenHouse;
  final Future<VenueDocumentsView> Function()? onLoadDocuments;
  final Future<VenueDocumentsView?> Function(VenueDocumentItem item)?
  onUploadDocument;
  final void Function(Uri uri)? onOpenUrl;
  final Future<bool> Function()? onPixReady;

  @override
  State<VenueFinanceStep> createState() => _VenueFinanceStepState();
}

class _VenueFinanceStepState extends State<VenueFinanceStep> {
  var _busy = false;
  var _subaccount = false;
  var _pixReady = false;
  String? _subaccountNote;
  VenueDocumentsView? _documents;

  @override
  void initState() {
    super.initState();
    if (widget.onPixReady != null) _refreshPix();
  }

  Future<void> _refreshPix() async {
    final ready = widget.onPixReady == null
        ? false
        : await widget.onPixReady!();
    if (!mounted) return;
    setState(() {
      _pixReady = ready;
      if (ready) _subaccount = true;
    });
    if (ready) await _loadDocuments();
  }

  Future<void> _provision() async {
    setState(() => _busy = true);
    final failure = await widget.onProvision();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure == null) {
        _subaccount = true;
        _subaccountNote = PartnerMessages.claimProvisionDone;
      } else {
        _subaccountNote = failure;
      }
    });
    if (failure == null) {
      await _loadDocuments();
      await _refreshPix();
    }
  }

  Future<void> _loadDocuments() async {
    final load = widget.onLoadDocuments;
    if (load == null) return;
    try {
      final view = await load();
      if (!mounted) return;
      setState(() => _documents = view);
    } on Object {
      if (!mounted) return;
      setState(() => _documents = VenueDocumentsView.unavailable);
    }
  }

  Future<void> _upload(VenueDocumentItem item) async {
    final upload = widget.onUploadDocument;
    if (upload == null) return;
    setState(() => _busy = true);
    try {
      final view = await upload(item);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (view != null) _documents = view;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      await _loadDocuments();
    }
  }

  String get _subaccountStatus {
    if (_subaccount && _pixReady) return PartnerMessages.claimStepReady;
    if (_subaccount) {
      return _subaccountNote ?? PartnerMessages.claimStepReady;
    }
    return _subaccountNote ?? PartnerMessages.claimStepPending;
  }

  String get _documentsStatus {
    if (!_subaccount) return PartnerMessages.claimStepWait;
    final view = _documents;
    if (view == null) return PartnerMessages.claimStepPending;
    if (view.approved) return PartnerMessages.claimStepApproved;
    if (!view.known || view.message != null) {
      return PartnerMessages.claimStepUnknown;
    }
    return PartnerMessages.claimStepPending;
  }

  String get _pixStatus {
    if (_pixReady) return PartnerMessages.claimStepPixReady;
    if (!_subaccount) return PartnerMessages.claimStepWait;
    return PartnerMessages.claimStepPending;
  }

  @override
  Widget build(BuildContext context) {
    final documents = _documents;
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
        const SizedBox(height: 16),
        Column(
          key: PartnerKeys.venueClaimChecklist,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ClaimStep(
              titleKey: PartnerKeys.venueClaimStepSubaccount,
              title: PartnerMessages.claimStepSubaccount,
              status: _subaccountStatus,
              child: FilledButton(
                key: PartnerKeys.venueClaimProvision,
                onPressed: _busy || _subaccount ? null : _provision,
                child: const Text(PartnerMessages.claimProvision),
              ),
            ),
            _ClaimStep(
              titleKey: PartnerKeys.venueClaimStepDocuments,
              title: PartnerMessages.claimStepDocuments,
              status: _documentsStatus,
              child: _subaccount && documents != null
                  ? VenueDocumentsCard(
                      view: documents,
                      busy: _busy,
                      onOpen: widget.onOpenUrl ?? (_) {},
                      onUpload: _upload,
                      onRefresh: _loadDocuments,
                    )
                  : null,
            ),
            _ClaimStep(
              titleKey: PartnerKeys.venueClaimStepPix,
              title: PartnerMessages.claimStepPix,
              status: _pixStatus,
              child: const Text(PartnerMessages.claimBankHint),
            ),
          ],
        ),
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

class _ClaimStep extends StatelessWidget {
  const _ClaimStep({
    required this.titleKey,
    required this.title,
    required this.status,
    this.child,
  });

  final Key titleKey;
  final String title;
  final String status;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        key: titleKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(status),
          if (child != null) ...[const SizedBox(height: 8), child!],
        ],
      ),
    );
  }
}
