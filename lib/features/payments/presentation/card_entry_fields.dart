import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/domain/player_cpf.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';

/// Campos do cartão novo. O número só segue para `tokenize-card`.
class CardEntryControllers {
  CardEntryControllers()
    : holder = TextEditingController(),
      holderCpf = TextEditingController(),
      number = TextEditingController(),
      month = TextEditingController(),
      year = TextEditingController(),
      securityCode = TextEditingController();

  final TextEditingController holder;
  final TextEditingController holderCpf;
  final TextEditingController number;
  final TextEditingController month;
  final TextEditingController year;
  final TextEditingController securityCode;
  var requireHolderDocument = false;
  var ownCard = false;

  void dispose() {
    holder.dispose();
    holderCpf.dispose();
    number.dispose();
    month.dispose();
    year.dispose();
    securityCode.dispose();
  }

  void clear() {
    holder.clear();
    holderCpf.clear();
    number.clear();
    month.clear();
    year.clear();
    securityCode.clear();
    ownCard = false;
  }

  bool get started {
    return holder.text.trim().isNotEmpty ||
        holderCpf.text.trim().isNotEmpty ||
        number.text.trim().isNotEmpty ||
        month.text.trim().isNotEmpty ||
        year.text.trim().isNotEmpty ||
        securityCode.text.trim().isNotEmpty;
  }

  /// Nulo quando o CPF do titular não entra na conta. Não repete o número.
  String? get holderDocumentProblem {
    if (!requireHolderDocument) return null;
    if (holderCpf.text.trim().isEmpty) return 'Informe o CPF do titular.';
    if (playerCpfDigits(holderCpf.text) == null) {
      return 'CPF do titular inválido.';
    }
    return null;
  }

  /// Nulo quando falta algum campo ou o número não tem 13 a 19 dígitos.
  CardDraft? get draft {
    final name = holder.text.trim();
    final digits = number.text.replaceAll(RegExp(r'\D'), '');
    final monthText = month.text.trim();
    final yearText = year.text.trim();
    final code = securityCode.text.trim();
    final monthNumber = int.tryParse(monthText);
    final monthOk =
        monthNumber != null && monthNumber >= 1 && monthNumber <= 12;
    final holderDigits = playerCpfDigits(holderCpf.text);
    if (name.isEmpty ||
        digits.length < 13 ||
        digits.length > 19 ||
        !monthOk ||
        !RegExp(r'^\d{4}$').hasMatch(yearText) ||
        !RegExp(r'^\d{3,4}$').hasMatch(code) ||
        (requireHolderDocument && holderDigits == null)) {
      return null;
    }
    return CardDraft(
      holderName: name,
      number: digits,
      expiryMonth: monthText.padLeft(2, '0'),
      expiryYear: yearText,
      ccv: code,
      holderCpfCnpj: holderDigits ?? '',
    );
  }
}

class CardEntryFields extends StatelessWidget {
  const CardEntryFields({super.key, required this.controllers, this.onOwnCard});

  final CardEntryControllers controllers;
  final ValueChanged<bool>? onOwnCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final real = controllers.requireHolderDocument;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (real) ...[
          Text(
            'Pode ser o cartão de outra pessoa, como pai ou empresa.',
            key: AppKeys.cardHolderNote,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          CheckboxListTile(
            key: AppKeys.cardOwn,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: controllers.ownCard,
            onChanged: onOwnCard == null
                ? null
                : (value) => onOwnCard!(value ?? false),
            title: const Text('O cartão é meu'),
          ),
          Text(
            'Nome do titular (como no cartão)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
        ],
        TextField(
          key: AppKeys.cardHolder,
          controller: controllers.holder,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: real ? null : 'Nome no cartão',
          ),
        ),
        if (real) ...[
          const SizedBox(height: 12),
          Text('CPF do titular', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          TextField(
            key: AppKeys.cardHolderCpf,
            controller: controllers.holderCpf,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: const InputDecoration(hintText: '000.000.000-00'),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          key: AppKeys.cardNumber,
          controller: controllers.number,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Número'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: AppKeys.cardMonth,
                controller: controllers.month,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Mês'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: AppKeys.cardYear,
                controller: controllers.year,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Ano'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: AppKeys.cardSecurity,
          controller: controllers.securityCode,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Código de segurança'),
        ),
      ],
    );
  }
}
