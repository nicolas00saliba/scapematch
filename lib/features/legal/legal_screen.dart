import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/legal/legal_documents.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final String document;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (document) {
      'privacidade' => (
        LegalDocuments.privacyTitle,
        LegalDocuments.privacyBody,
      ),
      'reembolso' => (LegalDocuments.refundTitle, LegalDocuments.refundBody),
      _ => (LegalDocuments.termsTitle, LegalDocuments.termsBody),
    };
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            LegalDocuments.reviewBanner,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: status.onAlertContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(body.trim(), style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
