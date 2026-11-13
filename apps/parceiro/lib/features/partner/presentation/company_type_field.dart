import 'package:flutter/material.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

/// Tipo de empresa da subconta Asaas. Pessoa física não vê a pergunta:
/// a provisão não envia `companyType` no CPF.
class CompanyTypeField extends StatelessWidget {
  const CompanyTypeField({
    super.key,
    required this.documentKind,
    required this.value,
    required this.onChanged,
  });

  static const fieldKey = Key('partner-company-type');

  final String documentKind;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (documentKind != 'cnpj') return const SizedBox.shrink();
    final selected = VenueDraft.companyTypes.containsKey(value)
        ? value
        : 'LIMITED';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: fieldKey,
        initialValue: selected,
        decoration: const InputDecoration(
          labelText: 'Tipo de empresa',
          helperText: 'O Asaas usa este tipo na conta da casa.',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final entry in VenueDraft.companyTypes.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}
