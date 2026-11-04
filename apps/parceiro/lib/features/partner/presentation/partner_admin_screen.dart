import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerAdminScreen extends ConsumerStatefulWidget {
  const PartnerAdminScreen({super.key});

  @override
  ConsumerState<PartnerAdminScreen> createState() => _PartnerAdminScreenState();
}

class _PartnerAdminScreenState extends ConsumerState<PartnerAdminScreen> {
  List<Map<String, dynamic>> _rows = const [];
  final _private = <String, Map<String, dynamic>>{};
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await listPendingVenues();
      for (final row in rows) {
        final id = row['id'] as String;
        _private[id] = await readVenuePrivate(id) ?? const {};
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler as casas pendentes.';
      });
    }
  }

  Future<void> _review(String id, String status) async {
    final error = await reviewVenue(venueId: id, status: status);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(partnerSessionProvider);
    final theme = Theme.of(context);
    return AppScaffold(
      desktopMaxWidth: 840,
      appBar: AppBar(
        title: const Text(PartnerMessages.adminTitle),
        actions: [
          if (session != null && session.hasApprovedHouse)
            TextButton(
              onPressed: () =>
                  ref.read(partnerPreferDeskProvider.notifier).open(),
              child: const Text(PartnerMessages.openHouse),
            ),
          TextButton(
            onPressed: () =>
                ref.read(partnerSessionProvider.notifier).signOut(),
            child: const Text(PartnerMessages.signOut),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: PartnerKeys.partnerAdmin,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (_error != null) ...[
                  Text(_error!),
                  const SizedBox(height: 12),
                ],
                if (_rows.isEmpty)
                  Text(
                    PartnerMessages.adminEmpty,
                    style: theme.textTheme.titleMedium,
                  ),
                for (final row in _rows) ...[
                  _VenueCard(
                    row: row,
                    privateFields: _private[row['id']] ?? const {},
                    onApprove: () => _review(row['id'] as String, 'approved'),
                    onReject: () => _review(row['id'] as String, 'rejected'),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.row,
    required this.privateFields,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> row;
  final Map<String, dynamic> privateFields;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = row['document_kind'] ?? '';
    final document = privateFields['document_number'] ?? '';
    final phone = privateFields['phone'] ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row['name']}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${row['street_address']}, ${row['address_number']} · ${row['neighborhood']}',
            ),
            Text('${row['category']} · ${row['city_id']}'),
            if ('$kind'.isNotEmpty) Text('$kind $document'),
            if ('$phone'.isNotEmpty) Text('Tel. $phone'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: PartnerKeys.partnerApprove,
                  onPressed: onApprove,
                  child: const Text(PartnerMessages.approve),
                ),
                OutlinedButton(
                  onPressed: onReject,
                  child: const Text(PartnerMessages.reject),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
