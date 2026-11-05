import 'package:scapematch/features/account/domain/player_cpf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O perfil guarda o CPF. A tela só precisa saber se ele já existe.
abstract class PlayerCpfStore {
  Future<bool> hasCpf();

  /// Nulo quando guardou. A mensagem não repete o número.
  Future<String?> save(String raw);
}

class MemoryPlayerCpfStore implements PlayerCpfStore {
  MemoryPlayerCpfStore({this.saved = false});

  bool saved;
  String? digits;

  @override
  Future<bool> hasCpf() async => saved;

  @override
  Future<String?> save(String raw) async {
    final next = playerCpfDigits(raw);
    if (next == null) return 'CPF inválido.';
    digits = next;
    saved = true;
    return null;
  }
}

class SupabasePlayerCpfStore implements PlayerCpfStore {
  SupabasePlayerCpfStore(this.client);

  final SupabaseClient client;

  @override
  Future<bool> hasCpf() async {
    final status = await client.rpc('my_cpf_status');
    return status == true;
  }

  @override
  Future<String?> save(String raw) async {
    final digits = playerCpfDigits(raw);
    if (digits == null) return 'CPF inválido.';
    try {
      final ok = await client.rpc('set_my_cpf', params: {'p_cpf': digits});
      if (ok != true) return 'Não foi possível guardar o CPF.';
      return null;
    } on PostgrestException {
      return 'Não foi possível guardar o CPF.';
    }
  }
}
