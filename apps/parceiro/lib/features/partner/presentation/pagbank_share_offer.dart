import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_share_repository.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Oferta "usar a mesma conta PagBank de outra cidade", acima do cadastro
/// PagBank da cidade aberta. Some quando não há outra cidade com conta ou
/// quando esta já tem conta.
class PagbankShareOffer extends ConsumerStatefulWidget {
  const PagbankShareOffer({
    super.key,
    required this.venueId,
    required this.onShared,
  });

  final String venueId;
  final VoidCallback onShared;

  @override
  ConsumerState<PagbankShareOffer> createState() => _PagbankShareOfferState();
}

class _PagbankShareOfferState extends ConsumerState<PagbankShareOffer> {
  List<PagbankShareSource> _sources = const [];
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.venueId.isEmpty) return;
    final sources = await ref
        .read(pagbankShareRepositoryProvider)
        .sources(widget.venueId);
    if (!mounted) return;
    setState(() => _sources = sources);
  }

  Future<void> _use(PagbankShareSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(PagbankShareMessages.confirmTitle),
        content: const Text(PagbankShareMessages.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(PagbankShareMessages.cancel),
          ),
          FilledButton(
            key: PartnerKeys.pagbankShareConfirm,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(PagbankShareMessages.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(pagbankShareRepositoryProvider)
        .share(widget.venueId, source.venueId);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? PagbankShareMessages.done)),
    );
    if (error == null) {
      setState(() => _sources = const []);
      widget.onShared();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      key: PartnerKeys.pagbankShareOffer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              PagbankShareMessages.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(PagbankShareMessages.body),
            const SizedBox(height: 12),
            for (final source in _sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  key: PartnerKeys.pagbankShareUse(source.venueId),
                  onPressed: _busy ? null : () => _use(source),
                  child: Text(PagbankShareMessages.button(source)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
