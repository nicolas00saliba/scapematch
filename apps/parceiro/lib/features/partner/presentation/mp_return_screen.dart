import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/web/browser_path.dart';
import 'package:scapematch_parceiro/features/partner/data/mp_oauth_return.dart';
import 'package:scapematch_parceiro/features/partner/data/provider_payments.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// A tela que o Mercado Pago abre em `/mp-retorno`.
class MpReturnScreen extends ConsumerStatefulWidget {
  const MpReturnScreen({super.key, required this.uri, this.onFinished});

  final Uri uri;
  final VoidCallback? onFinished;

  @override
  ConsumerState<MpReturnScreen> createState() => _MpReturnScreenState();
}

class _MpReturnScreenState extends ConsumerState<MpReturnScreen> {
  String? _message;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    final session = ref.read(partnerSessionProvider);
    final request = readMpOauthReturn(
      widget.uri,
      sessionHouseId: session?.houseId,
    );
    if (request.outcome != MpOauthReturnOutcome.connect) {
      _busy = false;
      _message = request.outcome == MpOauthReturnOutcome.denied
          ? PartnerMessages.mpReturnDenied
          : PartnerMessages.mpReturnMissing;
      replaceBrowserPath(mpReturnHomePath(widget.uri));
      return;
    }
    _connect(request);
  }

  Future<void> _connect(MpOauthReturnRequest request) async {
    try {
      await ref.read(providerPaymentsRepositoryProvider).completeMpOauth(
            venueId: request.venueId!,
            code: request.code!,
            state: request.state!,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = PartnerMessages.mpReturnSuccess;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = PartnerMessages.mpReturnFailed;
      });
    }
    replaceBrowserPath(mpReturnHomePath(widget.uri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: PartnerKeys.mpReturn,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const CircularProgressIndicator(),
              if (_message != null) ...[
                Text(
                  _message!,
                  key: PartnerKeys.mpReturnMessage,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: PartnerKeys.mpReturnBack,
                  onPressed: widget.onFinished,
                  child: const Text(PartnerMessages.mpReturnBack),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
