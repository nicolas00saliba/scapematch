import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/domain/player_cpf.dart';
import 'package:scapematch/providers/repositories.dart';

/// Pede o CPF antes do primeiro Pix ou cartão no modo real.
Future<bool> ensurePlayerCpf(BuildContext context, WidgetRef ref) async {
  if (!ref.read(backendPlanProvider).connectsSupabase) return true;
  if (await ref.read(playerCpfStoreProvider).hasCpf()) return true;
  if (!context.mounted) return false;
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (context) => const CpfScreen()),
  );
  return saved == true;
}

class CpfScreen extends ConsumerStatefulWidget {
  const CpfScreen({super.key});

  @override
  ConsumerState<CpfScreen> createState() => _CpfScreenState();
}

class _CpfScreenState extends ConsumerState<CpfScreen> {
  final _cpf = TextEditingController();
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _cpf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (playerCpfDigits(_cpf.text) == null) {
      setState(() => _error = 'CPF inválido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await ref.read(playerCpfStoreProvider).save(_cpf.text);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _saving = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RepaintBoundary(
      key: AppKeys.playerCpfScreen,
      child: Scaffold(
        appBar: AppBar(title: const Text('CPF')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Para pagar com Pix ou cartão, o Asaas precisa do seu CPF.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ele fica só no seu perfil. A demonstração não pede esse dado.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: AppKeys.playerCpf,
              controller: _cpf,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'CPF',
                hintText: '000.000.000-00',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: AppKeys.playerCpfError,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: AppKeys.playerCpfSave,
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar CPF'),
            ),
          ],
        ),
      ),
    );
  }
}
