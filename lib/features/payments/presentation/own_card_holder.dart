import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/presentation/cpf_screen.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/payments/presentation/card_entry_fields.dart';
import 'package:scapematch/providers/repositories.dart';

/// Copia nome e CPF do jogador para os campos do titular.
/// Devolve falso se o perfil não tiver CPF. Não registra o número.
Future<bool> fillOwnCardHolder({
  required BuildContext context,
  required WidgetRef ref,
  required CardEntryControllers entry,
}) async {
  if (!await ensurePlayerCpf(context, ref) || !context.mounted) return false;
  final own = await ref.read(playerCpfStoreProvider).ownDigits();
  final name = ref.read(currentUserProvider).displayName.trim();
  if (own == null || name.isEmpty) return false;
  entry.holder.text = name;
  entry.holderCpf.text = own;
  return true;
}
