import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:scapematch_admin/admin_otp_field.dart';
import 'package:scapematch_admin/admin_session.dart';
import 'package:scapematch_admin/admin_theme.dart';

class AdminMfaPage extends ConsumerStatefulWidget {
  const AdminMfaPage({super.key});

  @override
  ConsumerState<AdminMfaPage> createState() => _AdminMfaPageState();
}

class _AdminMfaPageState extends ConsumerState<AdminMfaPage> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    ref.listen(adminSessionProvider, (_, next) {
      final onCode =
          next.phase == AdminPhase.enroll || next.phase == AdminPhase.verify;
      if (!onCode || next.error == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _code.text.isEmpty) return;
        _code.clear();
      });
    });
    final enroll = session.phase == AdminPhase.enroll;
    return Scaffold(
      key: const Key('admin-mfa'),
      body: AutofillGroup(
        child: AdminAuthCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AdminMark(height: 112)),
              const SizedBox(height: 12),
              Text(
                enroll ? 'Cadastre o autenticador' : 'Código do autenticador',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                enroll
                    ? 'Leia o QR no app autenticador. O painel só abre depois do código.'
                    : 'Digite o código de 6 dígitos do autenticador para abrir o painel.',
                textAlign: TextAlign.center,
              ),
              if (enroll && session.qrCode != null) ...[
                const SizedBox(height: 16),
                Center(child: _Qr(session.qrCode!)),
              ],
              if (enroll && session.secret != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'No celular, copie a chave se não der para escanear o próprio QR.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  session.secret!,
                  key: const Key('admin-mfa-secret'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('admin-mfa-copy-secret'),
                  onPressed: session.busy
                      ? null
                      : () => _copySecret(session.secret!),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar chave'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O relógio do celular precisa estar em hora automática.',
                  key: Key('admin-mfa-clock-hint'),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              AdminOtpField(
                controller: _code,
                enabled: !session.busy,
                hasError: session.error != null,
                onCompleted: (_) => _submit(),
              ),
              if (session.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  session.error!,
                  key: const Key('admin-mfa-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('admin-mfa-confirm'),
                onPressed: session.busy ? null : _submit,
                child: Text(session.busy ? 'Conferindo…' : 'Confirmar'),
              ),
              TextButton(
                onPressed: session.busy
                    ? null
                    : () => ref.read(adminSessionProvider.notifier).signOut(),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (ref.read(adminSessionProvider).busy) return;
    ref.read(adminSessionProvider.notifier).confirmCode(_code.text);
  }

  Future<void> _copySecret(String secret) async {
    try {
      await Clipboard.setData(ClipboardData(text: secret));
    } on Object {
      if (!mounted) return;
      _snack('Não foi possível copiar a chave.');
      return;
    }
    if (!mounted) return;
    _snack('Chave copiada.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Qr extends StatelessWidget {
  const _Qr(this.qrCode);

  final String qrCode;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svgFromEnroll(qrCode),
      key: const Key('admin-mfa-qr'),
      width: 180,
      height: 180,
    );
  }
}

String svgFromEnroll(String qrCode) {
  const prefix = 'data:image/svg+xml;utf-8,';
  final raw = qrCode.startsWith(prefix)
      ? qrCode.substring(prefix.length)
      : qrCode;
  if (raw.startsWith('<')) return raw;
  return Uri.decodeFull(raw);
}
