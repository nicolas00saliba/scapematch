import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/sharing/group_link.dart';
import 'package:scapematch/features/groups/domain/group.dart';

/// Texto sugerido para WhatsApp e para o compartilhamento genérico.
String inviteMessage(Group group, {Uri? page, bool? onWeb}) {
  final link = groupLink(group.id, page: page, onWeb: onWeb);
  final open = group.openSeats;
  final spots = open == 1 ? '1 vaga restante' : '$open vagas restantes';
  return 'Vamos jogar ${group.roomName}?\n'
      '${group.houseName} · ${group.cityName}\n'
      '${formatSession(group.startsAt)}\n'
      '$spots\n'
      '$link';
}

/// Atalho do WhatsApp. O texto vai codificado na query.
String whatsAppShareUrl(String message) {
  return 'https://wa.me/?text=${Uri.encodeComponent(message)}';
}
