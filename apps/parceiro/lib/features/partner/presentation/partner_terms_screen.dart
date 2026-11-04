import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerTermsScreen extends ConsumerStatefulWidget {
  const PartnerTermsScreen({super.key});

  @override
  ConsumerState<PartnerTermsScreen> createState() =>
      _PartnerTermsScreenState();
}

class _PartnerTermsScreenState extends ConsumerState<PartnerTermsScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _accepted = false;
  String? _error;
  List<LegalAcceptance> _recorded = const [];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.length < 2 || !email.contains('@') || _password.text.length < 4) {
      setState(() {
        _error = 'Preencha o nome da casa, um e-mail e uma senha de 4 caracteres.';
      });
      return;
    }
    if (!_accepted) {
      setState(() => _error = PartnerLegal.termsRequired);
      return;
    }
    final when = DateTime.now();
    ref.read(partnerAcceptanceProvider.notifier).record(
      userId: email.toLowerCase(),
      at: when,
    );
    setState(() {
      _error = null;
      _recorded = [
        for (final code in partnerAcceptanceCodes)
          LegalAcceptance(
            userId: email.toLowerCase(),
            audience: 'partner',
            documentCode: code,
            documentVersion: legalDocumentVersion,
            acceptedAt: when,
          ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      desktopMaxWidth: AppScaffold.formMax,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Cadastro da casa'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            LegalDocuments.reviewBanner,
            key: PartnerKeys.partnerSignupBanner,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'O cadastro da casa só segue com o aceite. A versão e a data ficam registradas.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: PartnerKeys.partnerSignupName,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome da casa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.partnerSignupEmail,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.partnerSignupPassword,
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: PartnerKeys.partnerSignupTerms,
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: (value) => setState(() => _accepted = value ?? false),
            title: Text(
              'Li e aceito os termos do Parceiro, a privacidade e o cancelamento (versão $legalDocumentVersion).',
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => _open(
                  PartnerLegal.termsTitle,
                  PartnerLegal.termsBody,
                ),
                child: const Text('Termos do Parceiro'),
              ),
              TextButton(
                onPressed: () => _open(
                  LegalDocuments.privacyTitle,
                  LegalDocuments.privacyBody,
                ),
                child: const Text('Privacidade'),
              ),
              TextButton(
                onPressed: () => _open(
                  LegalDocuments.refundTitle,
                  LegalDocuments.refundBody,
                ),
                child: const Text('Cancelamento e reembolso'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: PartnerKeys.partnerSignupSubmit,
            onPressed: _recorded.isEmpty ? _submit : null,
            child: const Text('Cadastrar casa'),
          ),
          if (_recorded.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Aceite registrado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in _recorded)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${row.documentCode} · versão ${row.documentVersion} · ${_stamp(row.acceptedAt)}',
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Nesta demonstração a casa de exemplo continua sendo a do login. No servidor, accept_terms grava a mesma versão e a data.',
            ),
          ],
        ],
      ),
    );
  }

  void _open(String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PartnerLegalScreen(title: title, body: body),
      ),
    );
  }

  String _stamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year} $hour:$minute';
  }
}
