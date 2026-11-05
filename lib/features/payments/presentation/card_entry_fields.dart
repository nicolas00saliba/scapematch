import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';

/// Campos do cartão novo. O número só segue para `tokenize-card`.
class CardEntryControllers {
  CardEntryControllers()
    : holder = TextEditingController(),
      number = TextEditingController(),
      month = TextEditingController(),
      year = TextEditingController(),
      securityCode = TextEditingController();

  final TextEditingController holder;
  final TextEditingController number;
  final TextEditingController month;
  final TextEditingController year;
  final TextEditingController securityCode;

  void dispose() {
    holder.dispose();
    number.dispose();
    month.dispose();
    year.dispose();
    securityCode.dispose();
  }

  void clear() {
    holder.clear();
    number.clear();
    month.clear();
    year.clear();
    securityCode.clear();
  }

  bool get started {
    return holder.text.trim().isNotEmpty ||
        number.text.trim().isNotEmpty ||
        month.text.trim().isNotEmpty ||
        year.text.trim().isNotEmpty ||
        securityCode.text.trim().isNotEmpty;
  }

  /// Nulo quando falta algum campo ou o número não tem 13 a 19 dígitos.
  CardDraft? get draft {
    final name = holder.text.trim();
    final digits = number.text.replaceAll(RegExp(r'\D'), '');
    final monthText = month.text.trim();
    final yearText = year.text.trim();
    final code = securityCode.text.trim();
    final monthNumber = int.tryParse(monthText);
    final monthOk = monthNumber != null && monthNumber >= 1 && monthNumber <= 12;
    if (name.isEmpty ||
        digits.length < 13 ||
        digits.length > 19 ||
        !monthOk ||
        !RegExp(r'^\d{4}$').hasMatch(yearText) ||
        !RegExp(r'^\d{3,4}$').hasMatch(code)) {
      return null;
    }
    return CardDraft(
      holderName: name,
      number: digits,
      expiryMonth: monthText.padLeft(2, '0'),
      expiryYear: yearText,
      ccv: code,
    );
  }
}

class CardEntryFields extends StatelessWidget {
  const CardEntryFields({super.key, required this.controllers});

  final CardEntryControllers controllers;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          key: AppKeys.cardHolder,
          controller: controllers.holder,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nome no cartão'),
        ),
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
