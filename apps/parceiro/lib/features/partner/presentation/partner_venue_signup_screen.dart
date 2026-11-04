import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_registry.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_board.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_claim_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerVenueSignupScreen extends ConsumerStatefulWidget {
  const PartnerVenueSignupScreen({super.key});

  @override
  ConsumerState<PartnerVenueSignupScreen> createState() =>
      _PartnerVenueSignupScreenState();
}

class _PartnerVenueSignupScreenState
    extends ConsumerState<PartnerVenueSignupScreen> {
  final _name = TextEditingController();
  final _postalCode = TextEditingController();
  final _number = TextEditingController();
  final _document = TextEditingController();
  String _cityId = 'curitiba';
  List<VenueConflict> _conflicts = const [];
  String? _error;
  var _checked = false;
  var _sent = false;
  var _marked = false;

  @override
  void dispose() {
    _name.dispose();
    _postalCode.dispose();
    _number.dispose();
    _document.dispose();
    super.dispose();
  }

  VenueDraft get _draft => VenueDraft(
    ownerId: venueSignupOwnerId,
    name: _name.text,
    cityId: _cityId,
    postalCode: _postalCode.text,
    addressNumber: _number.text,
    document: _document.text,
  );

  bool get _blocked => _conflicts.any((conflict) => conflict.blocks);

  VenueConflict? get _claimTarget {
    for (final conflict in _conflicts) {
      if (conflict.type == venueConflictAddress && conflict.venueId != null) {
        return conflict;
      }
    }
    for (final conflict in _conflicts) {
      if (conflict.venueId != null) {
        return conflict;
      }
    }
    return null;
  }

  void _check() {
    final draft = _draft;
    final digits = normalizeDocument(draft.document);
    if (draft.name.trim().length < 2 ||
        resolveVenueCity(draft.cityId) == null ||
        normalizePostalCode(draft.postalCode).length != 8 ||
        draft.addressNumber.trim().isEmpty ||
        digits == null ||
        (digits.length != 11 && digits.length != 14)) {
      setState(() {
        _checked = false;
        _conflicts = const [];
        _error = PartnerMessages.invalidVenue;
      });
      return;
    }
    final conflicts = ref.read(venueRegistryProvider.notifier).check(draft);
    setState(() {
      _checked = true;
      _conflicts = conflicts;
      _error = null;
    });
  }

  void _submit() {
    final target = ref.read(venueRegistryProvider).duplicateTarget(_conflicts);
    try {
      ref
          .read(venueRegistryProvider.notifier)
          .submit(
            _draft,
            possibleDuplicateOf: _conflicts.isEmpty ? null : target,
          );
      setState(() {
        _sent = true;
        _marked = target != null;
        _error = null;
      });
    } on VenueDocumentBlocked {
      setState(() => _error = PartnerMessages.documentBlockedHidden);
    } on VenueLinkInvalid {
      setState(() => _error = PartnerMessages.invalidVenue);
    }
  }

  void _openClaim() {
    final target = _claimTarget;
    if (target?.venueId == null || target?.venueName == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PartnerVenueClaimScreen(
          venueId: target!.venueId!,
          venueName: target.venueName!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      appBar: AppBar(title: const Text(PartnerMessages.signupVenue)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 880 : 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 8 : 16, 8, wide ? 8 : 16, 28),
              children: [
                Text(
                  PartnerMessages.signupIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
                if (_sent) ...[
                  const SizedBox(height: 16),
                  _Sent(marked: _marked),
                ] else ...[
                  if (_checked && _conflicts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _DuplicateBanner(
                      conflicts: _conflicts,
                      blocked: _blocked,
                      onSubmit: _blocked ? null : _submit,
                      onClaim: _claimTarget == null ? null : _openClaim,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    key: PartnerKeys.venueName,
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: PartnerMessages.venueName,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: PartnerKeys.venueCity,
                    initialValue: _cityId,
                    decoration: const InputDecoration(
                      labelText: PartnerMessages.venueCity,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final city in venueCities)
                        DropdownMenuItem(value: city.$1, child: Text(city.$2)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _cityId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: PartnerKeys.venuePostalCode,
                          controller: _postalCode,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: PartnerMessages.venuePostalCode,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: PartnerKeys.venueNumber,
                          controller: _number,
                          decoration: const InputDecoration(
                            labelText: PartnerMessages.venueNumber,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: PartnerKeys.venueDocument,
                    controller: _document,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: PartnerMessages.venueDocument,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: PartnerKeys.venueFormError,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: PartnerKeys.venueCheck,
                    onPressed: _check,
                    child: const Text(PartnerMessages.checkVenue),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({
    required this.conflicts,
    required this.blocked,
    required this.onSubmit,
    required this.onClaim,
  });

  final List<VenueConflict> conflicts;
  final bool blocked;
  final VoidCallback? onSubmit;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    final scheme = theme.colorScheme;
    final background = blocked ? scheme.errorContainer : status.alertContainer;
    final foreground = blocked
        ? scheme.onErrorContainer
        : status.onAlertContainer;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final buttons = <Widget>[
      if (onSubmit != null)
        FilledButton(
          key: PartnerKeys.venueSubmitAnyway,
          style: FilledButton.styleFrom(
            backgroundColor: foreground,
            foregroundColor: background,
          ),
          onPressed: onSubmit,
          child: const Text(PartnerMessages.submitAnyway),
        ),
      if (onClaim != null)
        OutlinedButton(
          key: PartnerKeys.venueClaim,
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            side: BorderSide(color: foreground),
          ),
          onPressed: onClaim,
          child: const Text(PartnerMessages.claimTitle),
        ),
    ];
    return Material(
      key: PartnerKeys.venueDuplicateBanner,
      color: background,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocked ? Icons.block : Icons.warning_amber_rounded,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blocked
                        ? PartnerMessages.documentBlockedTitle
                        : PartnerMessages.duplicateTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final conflict in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _line(conflict),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
                ),
              ),
            if (!blocked)
              Text(
                PartnerMessages.duplicateHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.35,
                ),
              ),
            if (buttons.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (wide)
                Row(
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: buttons[i]),
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      buttons[i],
                    ],
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _line(VenueConflict conflict) {
    final name = conflict.venueName;
    if (conflict.type == venueConflictDocument) {
      if (name == null) {
        return PartnerMessages.documentBlockedHidden;
      }
      return PartnerMessages.documentBlockedNamed(name);
    }
    if (conflict.type == venueConflictAddress && name != null) {
      return PartnerMessages.addressWarning(name);
    }
    if (name != null) {
      return PartnerMessages.nameWarning(name);
    }
    return conflict.type;
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.marked});

  final bool marked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    return Material(
      key: PartnerKeys.venueSignupSent,
      color: status.successContainer,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          marked
              ? '${PartnerMessages.signupSent} ${PartnerMessages.signupMarked}'
              : PartnerMessages.signupSent,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: status.onSuccessContainer,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
