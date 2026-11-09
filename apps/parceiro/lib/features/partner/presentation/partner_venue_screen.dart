import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerVenueScreen extends ConsumerStatefulWidget {
  const PartnerVenueScreen({super.key});

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
  String _category = 'escape-room';
  String? _cityId = 'curitiba';
  List<City> _cities = knownCities;
  String? _error;
  var _busy = false;
  var _accepted = false;
  var _confirmDuplicate = false;
  List<String> _warnings = const [];

  @override
  void initState() {
    super.initState();
    if (!scapeUsesLiveBackend) return;
    Future<void>(() async {
      final cities = await ref.read(cityRepositoryProvider).listCities();
      if (!mounted || cities.isEmpty) return;
      setState(() {
        _cities = cities;
        _cityId ??= cities.first.id;
      });
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
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    await ref.read(partnerSessionProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      desktopMaxWidth: 640,
      appBar: AppBar(
        title: const Text('Cadastro da casa'),
        actions: [
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
          DropdownButtonFormField<String>(
            key: ValueKey('venue-city-$_cityId'),
            initialValue: _cities.any((city) => city.id == _cityId)
                ? _cityId
                : null,
            decoration: const InputDecoration(
              labelText: 'Cidade',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final city in _cities)
                DropdownMenuItem(value: city.id, child: Text(city.name)),
            ],
            onChanged: (value) => setState(() => _cityId = value),
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cnpj', label: Text('CNPJ')),
              ButtonSegment(value: 'cpf', label: Text('CPF')),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.partnerVenueDocument,
            controller: _document,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _kind == 'cpf' ? 'CPF' : 'CNPJ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
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
              helperText: 'O Asaas pede este valor para a conta da casa.',
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
            decoration: const InputDecoration(
              labelText: 'Código de indicação (opcional)',
              helperText: 'De um jogador ou de outra casa. Só neste cadastro. Não é o convite.',
              border: OutlineInputBorder(),
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
