import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_documents_card.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_pagbank_signup_card.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Explica que o valor fica na conta PagBank. Não há saque automático.
///
/// Não pede conta, chave Pix nem valor de saque. O cadastro da conta e os
/// documentos continuam aqui.
class VenueWithdrawalsPanel extends ConsumerStatefulWidget {
  const VenueWithdrawalsPanel({
    super.key,
    required this.venueId,
    this.email,
    this.onOpenPagBank,
  });

  final String venueId;
  final String? email;
  final void Function(Uri uri)? onOpenPagBank;

  static final pagBankUri = Uri.parse(PartnerMessages.receivePagBankUrl);

  @override
  ConsumerState<VenueWithdrawalsPanel> createState() =>
      _VenueWithdrawalsPanelState();
}

class _VenueWithdrawalsPanelState extends ConsumerState<VenueWithdrawalsPanel> {
  VenueDocumentsView _documents = VenueDocumentsView.hidden;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final documents = await _readDocuments();
    if (!mounted) return;
    setState(() => _documents = documents);
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
    final documents = await _readDocuments();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _documents = documents;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    assert(widget.venueId.isNotEmpty || widget.email == null);
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VenuePagbankSignupCard(
          venueId: widget.venueId,
          onOpen: widget.onOpenPagBank,
        ),
        const SizedBox(height: 28),
        Text(
          PartnerMessages.withdrawalsTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.withdrawalsBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 20),
        Text(
          PartnerMessages.receiveStepsTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (final step in const [
          PartnerMessages.receiveStepAccount,
          PartnerMessages.receiveStepMenu,
          PartnerMessages.receiveStepDestination,
          PartnerMessages.receiveStepEnable,
        ]) ...[
          Text(step, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: PartnerKeys.receiveOpenPagBank,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () {
              final open = widget.onOpenPagBank ?? launchExternalUrl;
              open(VenueWithdrawalsPanel.pagBankUri);
            },
            icon: Icon(Icons.open_in_new, color: scheme.onPrimary),
            label: const Text(PartnerMessages.receiveOpenPagBank),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 20),
        VenueDocumentsCard(
          view: _documents,
          busy: _busy,
          onOpen: launchExternalUrl,
          onUpload: _uploadDocument,
          onRefresh: _refreshDocuments,
        ),
      ],
    );
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
