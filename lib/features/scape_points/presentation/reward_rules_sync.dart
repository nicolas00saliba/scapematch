import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';

/// Busca a regra ao abrir, a cada quarto de hora e ao voltar ao primeiro plano.
class RewardRulesSync extends ConsumerStatefulWidget {
  const RewardRulesSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RewardRulesSync> createState() => _RewardRulesSyncState();
}

class _RewardRulesSyncState extends ConsumerState<RewardRulesSync>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!scapeUsesLiveBackend) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _refresh());
    Future<void>.microtask(_refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (scapeUsesLiveBackend) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    unawaited(ref.read(rewardRulesProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
