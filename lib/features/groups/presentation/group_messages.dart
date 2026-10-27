import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Portuguese copy for the logistics screens. Tests look these strings up
/// so a wording change is visible in one place.
abstract final class GroupMessages {
  static String get _hours => '${GroupRules.refundDeadline.inHours}';

  static String confirmedCount(int count) {
    if (count == 0) {
      return 'Nenhuma presença confirmada';
    }
    if (count == 1) {
      return '1 presença confirmada';
    }
    return '$count presenças confirmadas';
  }

  static String attendanceLabel(AttendanceStatus status) {
    return switch (status) {
      AttendanceStatus.joined => 'Entrou',
      AttendanceStatus.confirmed => 'Presença confirmada',
      AttendanceStatus.cancelled => 'Cancelou',
    };
  }

  static String participantSubtitle(Participant person) {
    final status = attendanceLabel(person.attendance);
    if (person.isCreator) {
      return 'Criou o grupo · $status';
    }
    return status;
  }

  static const paymentLabel = 'Pago (simulado)';

  static String? refundLabel(Participant person) {
    final hours = _hours;
    return switch (person.refundReason) {
      RefundReason.none => null,
      RefundReason.cancelledInTime =>
        'Reembolsado · saiu com $hours horas ou mais de antecedência',
      RefundReason.cancelledTooLate =>
        'Sem reembolso · saiu com menos de $hours horas de antecedência',
      RefundReason.organizerCancelledEvent =>
        'Reembolsado · o organizador cancelou o evento',
      RefundReason.organizerRemovedMember =>
        person.isLocalUser
            ? 'Reembolsado · o organizador removeu você do grupo'
            : 'Reembolsado · o organizador removeu esta pessoa',
    };
  }

  static String joinFailure(JoinFailureReason reason) {
    return switch (reason) {
      JoinFailureReason.full => 'Esse grupo já está cheio.',
      JoinFailureReason.alreadyJoined => 'Você já está neste grupo.',
      JoinFailureReason.notFound => 'Não encontramos esse grupo.',
      JoinFailureReason.alreadyStarted =>
        'Este grupo já começou. Não dá mais para entrar.',
      JoinFailureReason.overlapsAnotherGroup => 'Você já está em outro grupo nesse horário. Saia dele ou escolha outro horário.',
      JoinFailureReason.membershipClosed =>
        'Você já saiu deste grupo e não pode entrar de novo.',
      JoinFailureReason.groupCancelled => 'Este grupo foi cancelado.',
      JoinFailureReason.sessionEnded => 'Esta sessão já terminou.',
    };
  }

  static String createFailure(CreateGroupFailureReason reason) {
    return switch (reason) {
      CreateGroupFailureReason.exceedsRoomCapacity =>
        'O grupo ficou maior do que a sala permite.',
      CreateGroupFailureReason.belowMinimum =>
        'O grupo precisa de mais gente além de você.',
      CreateGroupFailureReason.unknownSelection =>
        'Confira cidade, casa, sala e horário.',
      CreateGroupFailureReason.duplicateSession =>
        'Já existe um grupo nessa sala nesse horário. Escolha outro horário.',
      CreateGroupFailureReason.alreadyStarted =>
        'Esse horário já passou. Escolha um horário que ainda não começou.',
      CreateGroupFailureReason.overlapsAnotherGroup => 'Você já está em outro grupo nesse horário. Escolha um horário que não se sobreponha.',
    };
  }

  static const alreadyStartedHint =
      'Esse horário já passou. Escolha um horário que ainda não começou.';

  static String editFailure(EditGroupFailureReason reason) {
    return switch (reason) {
      EditGroupFailureReason.notFound => 'Não encontramos esse grupo.',
      EditGroupFailureReason.notCreator =>
        'Só quem criou o grupo pode editá-lo.',
      EditGroupFailureReason.belowOccupancy =>
        'Não dá para ficar com menos vagas do que as pessoas que já entraram.',
      EditGroupFailureReason.belowMinimum =>
        'O grupo precisa de pelo menos 2 pessoas.',
      EditGroupFailureReason.exceedsRoomCapacity =>
        'O grupo não pode passar da capacidade da sala.',
      EditGroupFailureReason.noteTooLong =>
        'A observação passou de ${GroupRules.maxNoteLength} caracteres.',
      EditGroupFailureReason.groupCancelled =>
        'Este grupo foi cancelado e não pode mais ser editado.',
      EditGroupFailureReason.sessionEnded =>
        'Esta sessão já terminou e não pode mais ser editada.',
    };
  }

  static String get leaveWithRefundTitle => 'Sair do grupo?';

  static String get leaveWithRefundBody =>
      'Faltam $_hours horas ou mais para o início. Se você sair agora, o pagamento simulado volta integralmente e a vaga fica livre.';

  static String get leaveWithoutRefundTitle => 'Sair sem reembolso?';

  static String get leaveWithoutRefundBody =>
      'Falta menos de $_hours horas para o início. Se você sair agora, não há reembolso. A vaga fica livre para outra pessoa.';

  static const leaveWithRefundAction = 'Sair e receber reembolso';
  static const leaveWithoutRefundAction = 'Sair sem reembolso';
  static const keepSeatAction = 'Voltar';

  static String get deleteTitle => 'Excluir grupo?';

  static String get deleteBody =>
      'Excluir cancela o evento para todo mundo. Quem ainda está no grupo recebe reembolso integral, mesmo que falte menos de $_hours horas, porque o cancelamento é do organizador. O grupo sai das listas.';

  static const deleteAction = 'Excluir grupo';

  static String removeTitle(String name) => 'Remover $name?';

  static String removeBody(String name) =>
      'Remover $name cancela a vaga dessa pessoa. O reembolso é integral, porque a saída foi decisão do organizador.';

  static const removeAction = 'Remover';

  static const joinedBanner = 'Você está neste grupo';
  static const leftBanner = 'Você já saiu deste grupo';
  static const cancelledBanner =
      'O organizador cancelou este grupo. Quem estava inscrito recebe reembolso integral.';
  static const linkCopied = 'Link do grupo copiado.';
  static const linkFailed = 'Não foi possível copiar o link.';
  static const confirmSuccess = 'Presença confirmada.';
  static const leaveRefunded =
      'Você saiu do grupo. Reembolso simulado registrado.';
  static const leaveDenied = 'Você saiu do grupo. Sem reembolso.';
  static const deletedSnack =
      'Grupo excluído. Quem participava recebe reembolso integral.';
  static const removedSnack = 'Participante removido com reembolso integral.';
  static const savedSnack = 'Grupo atualizado.';
  static const actionFailed = 'Não foi possível completar a ação.';
}
