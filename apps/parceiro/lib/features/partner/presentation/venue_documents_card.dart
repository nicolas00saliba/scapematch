import 'package:flutter/material.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class VenueDocumentsCard extends StatelessWidget {
  const VenueDocumentsCard({
    super.key,
    required this.view,
    required this.busy,
    required this.onOpen,
    required this.onUpload,
    required this.onRefresh,
  });

  final VenueDocumentsView view;
  final bool busy;
  final void Function(Uri uri) onOpen;
  final void Function(VenueDocumentItem item) onUpload;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!view.visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hosted = view.onboardingUrl != null;
    final unsafe = view.documents.any(
      (item) => item.hosted && item.onboardingUrl == null,
    );
    final waiting =
        view.documents.isEmpty &&
        view.documentation == 'PENDING' &&
        view.message == null;
    return Material(
      key: PartnerKeys.venueDocuments,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              PartnerMessages.documentsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              view.approved
                  ? PartnerMessages.documentsApproved
                  : PartnerMessages.documentsPending,
            ),
            if (view.message != null) ...[
              const SizedBox(height: 8),
              const Text(PartnerMessages.documentsUnavailable),
            ],
            if (waiting) ...[
              const SizedBox(height: 8),
              const Text(PartnerMessages.documentsWait),
            ],
            if (view.blocksWithdraw) ...[
              const SizedBox(height: 8),
              Text(PartnerMessages.documentsBlockWithdraw),
            ],
            for (final item in view.documents) ...[
              const SizedBox(height: 12),
              Text(
                '${item.title.isEmpty ? item.type : item.title} · ${PartnerMessages.documentStatus(item.status)}',
              ),
              if (item.description.isNotEmpty) Text(item.description),
              if (item.upload)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: PartnerKeys.venueDocumentUpload,
                    style: _target(),
                    onPressed: busy ? null : () => onUpload(item),
                    child: const Text(PartnerMessages.documentsSend),
                  ),
                ),
            ],
            if (hosted) ...[
              const SizedBox(height: 8),
              const Text(PartnerMessages.documentsHosted),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: PartnerKeys.venueDocumentOnboarding,
                  style: _target(),
                  onPressed: busy
                      ? null
                      : () => onOpen(Uri.parse(view.onboardingUrl!)),
                  child: const Text(PartnerMessages.documentsOpen),
                ),
              ),
            ] else if (view.documents.any((item) => item.upload)) ...[
              const SizedBox(height: 8),
              const Text(PartnerMessages.documentsUpload),
            ],
            if (unsafe) ...[
              const SizedBox(height: 8),
              const Text(PartnerMessages.documentsUnsafe),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: PartnerKeys.venueDocumentRefresh,
                style: _target(),
                onPressed: busy ? null : onRefresh,
                child: const Text(PartnerMessages.documentsRefresh),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle _target() {
  return TextButton.styleFrom(
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    tapTargetSize: MaterialTapTargetSize.padded,
    alignment: Alignment.centerLeft,
  );
}
