import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/auth/data/password_recovery.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/new_password_screen.dart';

/// Troca o app pela tela de senha nova enquanto o link de recuperação vale.
class PasswordRecoveryGate extends StatefulWidget {
  const PasswordRecoveryGate({
    super.key,
    required this.child,
    required this.savePassword,
  });

  final Widget child;
  final Future<String?> Function(String password) savePassword;

  @override
  State<PasswordRecoveryGate> createState() => _PasswordRecoveryGateState();
}

class _PasswordRecoveryGateState extends State<PasswordRecoveryGate> {
  @override
  void initState() {
    super.initState();
    passwordRecoverySignal.addListener(_rebuild);
  }

  @override
  void dispose() {
    passwordRecoverySignal.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<String?> _save(String password) async {
    final error = await widget.savePassword(password);
    if (error == null) passwordRecoverySignal.clear();
    return error;
  }

  @override
  Widget build(BuildContext context) {
    if (!passwordRecoverySignal.pending) return widget.child;
    return NewPasswordScreen(onSave: _save);
  }
}

/// Atalho do jogador: grava com [AuthController.changePassword].
class PlayerPasswordRecovery extends ConsumerWidget {
  const PlayerPasswordRecovery({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PasswordRecoveryGate(
      savePassword: (password) {
        return ref
            .read(authSessionProvider.notifier)
            .changePassword(password: password);
      },
      child: child,
    );
  }
}
