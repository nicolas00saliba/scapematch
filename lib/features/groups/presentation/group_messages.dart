import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
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

  static const simulatedNotice = 'Pagamento simulado, nada é cobrado';

  static const simulatedPixNotice = 'Pix simulado. O código abaixo não cobra.';

  static const livePixHint = 'O código Pix vem do Asaas quando você confirma.';

  static const livePixNotice =
      'O Pix é pago agora. Se o grupo não confirmar, o valor volta.';

  static const livePixReady = 'Pix do Asaas. Escaneie o QR ou copie o código.';

  static const simulatePayment = 'Simular pagamento';

  static const generatePix = 'Gerar Pix';

  static const payWithCard = 'Pagar com cartão';

  static const chargeOnlyIfCloses = 'Você só é cobrado se o grupo confirmar.';

  static const holdReleased = 'Valor liberado, nada foi cobrado';

  static String paymentStatus(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.pending => 'Pendente',
      PaymentStatus.reserved => 'Reservado',
      PaymentStatus.paid => 'Pago',
      PaymentStatus.released => 'Liberado',
    };
  }

  static String paidProgress(int paid, int seated) {
    if (seated <= 0 || paid <= 0) {
      return 'Ninguém pagou ainda';
    }
    if (paid == 1) {
      return '1 de $seated pagou';
    }
    return '$paid de $seated pagaram';
  }

  static String reservedProgress(int reserved, int seated) {
    if (seated <= 0 || reserved <= 0) {
      return 'Ninguém reservou ainda';
    }
    return '$reserved de $seated reservaram';
  }

  /// Aberto: quem separou o valor. Fechado: quem já foi cobrado.
  static String shareProgress({
    required bool closed,
    required int paid,
    required int reserved,
    required int seated,
  }) {
    if (closed) {
      return paidProgress(paid, seated);
    }
    return reservedProgress(reserved, seated);
  }

  static String paymentPolicy({required bool closed, required int hours}) {
    if (!closed) {
      return 'Se o grupo não confirmar, o valor reservado é liberado automaticamente.';
    }
    return 'Cancelar com $hours h ou mais de antecedência devolve o pagamento.';
  }

  static String payMyShare(String price) => 'Pagar minha parte ($price)';

  static const houseCannotReceive =
      'A casa ainda não pode receber';

  static const yourSharePending = 'Sua parte está pendente';
  static const yourShareReserved =
      'Valor reservado. Você só é cobrado se o grupo confirmar.';
  static const yourSharePaid = 'Sua parte está paga';
  static const yourShareReleased = 'Valor liberado, nada foi cobrado';

  static String yourShare(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.pending => yourSharePending,
      PaymentStatus.reserved => yourShareReserved,
      PaymentStatus.paid => yourSharePaid,
      PaymentStatus.released => yourShareReleased,
    };
  }

  static String closeWith(int seated) => 'Fechar com $seated pessoas';

  static String roomMinimum(int minimum) => 'Mínimo da sala: $minimum';

  static const closeBody =
      'Cada pessoa paga só a própria parte. O grupo fecha agora e a reserva vira cobrança.';

  static const cannotDeleteYet = 'Exclusão bloqueada (menos de 2 h)';

  static const leaveUnpaidBody =
      'Você ainda não pagou esta parte. Sair agora só libera a vaga. Não há valor para devolver.';

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
      RefundReason.groupDidNotClose =>
        person.payment == PaymentStatus.released
            ? holdReleased
            : 'Reembolsado · o grupo não confirmou até o prazo',
      RefundReason.holdReleased => holdReleased,
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
      JoinFailureReason.blocked => 'Alguém deste grupo bloqueou a sua conta.',
      JoinFailureReason.restricted => 'A conta está em pausa por faltas sem aviso. Tente de novo quando a pausa acabar.',
      JoinFailureReason.seatReserved => seatReserved,
      JoinFailureReason.offerExpired => offerExpired,
      JoinFailureReason.partyDoesNotFit =>
        'Não há vagas para a turma inteira. Ninguém entrou.',
      JoinFailureReason.companionNotFriend =>
        'Só dá para entrar com quem já aceitou a mesma turma.',
      JoinFailureReason.companionUnavailable =>
        'Alguém da turma não pode entrar nesse horário. Ninguém entrou.',
      JoinFailureReason.deadlinePassed => 'O prazo deste grupo acabou.',
    };
  }

  static String createFailure(CreateGroupFailureReason reason) {
    return switch (reason) {
      CreateGroupFailureReason.exceedsRoomCapacity =>
        'O grupo ficou maior do que a sala permite.',
      CreateGroupFailureReason.belowMinimum =>
        'O grupo precisa de mais gente além de você.',
      CreateGroupFailureReason.belowRoomMinimum =>
        'O total de vagas ficou abaixo do mínimo da sala.',
      CreateGroupFailureReason.unknownSelection =>
        'Confira cidade, casa, sala e horário.',
      CreateGroupFailureReason.duplicateSession =>
        'Já existe um grupo nessa sala nesse horário. Escolha outro horário.',
      CreateGroupFailureReason.alreadyStarted =>
        'Esse horário já passou. Escolha um horário que ainda não começou.',
      CreateGroupFailureReason.tooCloseToStart => tooCloseToStart,
      CreateGroupFailureReason.overlapsAnotherGroup => 'Você já está em outro grupo nesse horário. Escolha um horário que não se sobreponha.',
      CreateGroupFailureReason.crewLeavesNoOpenSeat =>
        'A turma ocuparia todas as vagas. Deixe ao menos uma aberta.',
      CreateGroupFailureReason.companionNotFriend =>
        'Só dá para levar quem já aceitou a mesma turma.',
      CreateGroupFailureReason.companionUnavailable =>
        'Alguém da turma não pode nesse horário.',
      CreateGroupFailureReason.payoutPending => 'Conta de recebimento pendente',
    };
  }

  static const alreadyStartedHint =
      'Esse horário já passou. Escolha um horário que ainda não começou.';

  static const tooCloseToStart =
      'Falta 1 h ou menos para o início. Escolha um horário com mais antecedência, para o grupo ter prazo de confirmar.';

  static String editFailure(EditGroupFailureReason reason) {
    return switch (reason) {
      EditGroupFailureReason.notFound => 'Não encontramos esse grupo.',
      EditGroupFailureReason.notCreator =>
        'Só quem criou o grupo pode editá-lo.',
      EditGroupFailureReason.belowOccupancy =>
        'Não dá para ficar com menos vagas do que as pessoas que já entraram.',
      EditGroupFailureReason.belowMinimum =>
        'O grupo precisa de pelo menos 2 pessoas.',
      EditGroupFailureReason.belowRoomMinimum =>
        'O total de vagas ficou abaixo do mínimo da sala.',
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

  /// The dialog used [preview] and the repository, which decides, stored
  /// the other outcome because the clock moved while the dialog was open.
  static String leavePreviewChanged({required bool refunded}) {
    if (refunded) {
      return 'O horário mudou enquanto o aviso estava aberto. Você saiu do grupo e o reembolso simulado foi registrado.';
    }
    return 'O horário mudou enquanto o aviso estava aberto. Você saiu do grupo e não há reembolso.';
  }

  static const sessionAlreadyStarted = 'A sessão já começou.';

  static String deleteFailure(DeleteGroupFailureReason reason) {
    return switch (reason) {
      DeleteGroupFailureReason.notFound => 'Não encontramos esse grupo.',
      DeleteGroupFailureReason.notCreator =>
        'Só quem criou o grupo pode excluí-lo.',
      DeleteGroupFailureReason.alreadyCancelled =>
        'Este grupo já foi cancelado.',
      DeleteGroupFailureReason.sessionStarted => sessionAlreadyStarted,
      DeleteGroupFailureReason.sessionEnded => 'Esta sessão já terminou.',
      DeleteGroupFailureReason.tooCloseToDelete => cannotDeleteYet,
    };
  }

  static String removeFailure(RemoveMemberFailureReason reason) {
    return switch (reason) {
      RemoveMemberFailureReason.notFound => 'Não encontramos esse grupo.',
      RemoveMemberFailureReason.notCreator =>
        'Só quem criou o grupo pode remover alguém.',
      RemoveMemberFailureReason.memberNotFound =>
        'Essa pessoa não está mais no grupo.',
      RemoveMemberFailureReason.cannotRemoveCreator =>
        'Quem criou o grupo não pode ser removido.',
      RemoveMemberFailureReason.groupCancelled => 'Este grupo foi cancelado.',
      RemoveMemberFailureReason.sessionStarted => sessionAlreadyStarted,
      RemoveMemberFailureReason.sessionEnded => 'Esta sessão já terminou.',
    };
  }

  static String get deleteTitle => 'Excluir grupo?';

  static String get deleteBody =>
      'Excluir cancela o evento para todo mundo. Quem ainda está no grupo recebe reembolso integral, mesmo que falte menos de $_hours horas, porque o cancelamento é do organizador. O grupo sai das listas.';

  static const deleteAction = 'Excluir grupo';

  static String removeTitle(String name) => 'Remover $name?';

  static String removeBody(String name) =>
      'Remover $name cancela a vaga dessa pessoa. O reembolso é integral, porque a saída foi decisão do organizador.';

  static const removeAction = 'Remover';

  static const signInToSeeGroups = 'Entre para ver seus grupos';
  static const signInToSeeGroupsBody =
      'Esta lista é da sua conta. Sem entrar, ela não mostra o usuário de exemplo.';
  static const signIn = 'Entrar';

  static const joinedBanner = 'Você está neste grupo';
  static const leftBanner = 'Você já saiu deste grupo';
  static const cancelledBanner =
      'O organizador cancelou este grupo. Quem estava inscrito recebe reembolso integral.';
  static const linkCopied = 'Link do grupo copiado.';
  static const inviteBecameFull =
      'O grupo lotou antes de você entrar. A vaga não ficou sua.';
  static const inviteImageLater =
      'O cartão como imagem ainda não é enviado. Use o link.';
  static const confirmSuccess = 'Presença confirmada.';
  static const leaveRefunded =
      'Você saiu do grupo. Reembolso simulado registrado.';
  static const leaveDenied = 'Você saiu do grupo. Sem reembolso.';
  static const deletedSnack =
      'Grupo excluído. Quem participava recebe reembolso integral.';
  static const removedSnack = 'Participante removido com reembolso integral.';
  static const savedSnack = 'Grupo atualizado.';
  static const actionFailed = 'Não foi possível completar a ação.';

  static const readyToReserve = 'Pronto para reservar';
  static const missedCloseBanner =
      'O grupo não atingiu o mínimo até o prazo e foi cancelado. O reembolso simulado é integral.';
  static const waitlistJoin = 'Entrar na lista de espera';
  static const waitlistAccept = 'Aceitar a vaga';
  static const waitlistDecline = 'Recusar a vaga';
  static const waitlistJoined = 'Você entrou na lista de espera.';
  static const waitlistDeclined =
      'Você recusou a vaga. Ela segue para a próxima pessoa.';
  static const seatReserved =
      'Essa vaga está reservada para quem recebeu a oferta.';
  static const offerExpired = 'O prazo para aceitar a vaga acabou.';
  static const attendanceOptional =
      'Confirmar presença é opcional. Não tocar nesse botão não conta como falta. A falta sem aviso só entra quando a casa marcar, e isso ainda não acontece nesta versão.';
  static const openMaps = 'Abrir no Google Maps';
  static const openWaze = 'Abrir no Waze';
  static const report = 'Denunciar';
  static const block = 'Bloquear';
  static const blockedSnack =
      'Pessoa bloqueada. Ela some dos seus grupos e dos cartões da Home, e não entra em grupo em que você esteja.';
  static const reportedSnack =
      'Denúncia registrada neste exemplo. Ninguém é punido de verdade.';

  static String seatCount(int filled, int total) => '$filled/$total';

  /// "N jogadores · mín. A · máx. B". Um jogador fica no singular.
  static String playerBand({
    required int filled,
    required int minimum,
    required int maximum,
  }) {
    final people = filled == 1 ? '1 jogador' : '$filled jogadores';
    return '$people · mín. $minimum · máx. $maximum';
  }

  static String bandStatus({
    required int filled,
    required int minimum,
    required int maximum,
    bool confirmed = false,
  }) {
    if (filled >= maximum) {
      return 'Lotado';
    }
    if (confirmed || filled >= minimum) {
      final left = maximum - filled;
      if (left == 1) {
        return 'Confirmado — ainda cabe 1';
      }
      return 'Confirmado — ainda cabem $left';
    }
    final missing = minimum - filled;
    if (missing <= 1) {
      return 'Falta 1 para confirmar';
    }
    return 'Faltam $missing para confirmar';
  }

  static String roomBounds({required int minimum, required int maximum}) {
    return 'Sala: mín. $minimum · máx. $maximum';
  }

  static String hostTarget(int target) => 'Host quer $target para fechar';

  static String roomAccepts({
    required int roomMinimum,
    required int roomMaximum,
    required int minimum,
    required int maximum,
  }) {
    return 'A sala aceita de $roomMinimum a $roomMaximum pessoas. '
        'O grupo confirma com $minimum e segue aberto até $maximum.';
  }

  static String allowedTarget({required int minimum, required int maximum}) {
    return 'A sala aceita de $minimum a $maximum pessoas. '
        'Escolha o mínimo para confirmar e o máximo, contando você. '
        'Os dois podem ser iguais.';
  }

  static String spotsUntilClose(int missing) {
    if (missing <= 0) {
      return 'Lotado';
    }
    if (missing == 1) {
      return 'Falta 1 para confirmar';
    }
    return 'Faltam $missing para confirmar';
  }

  static String phaseLabel(
    GroupPhase phase, {
    required int filled,
    required int minimum,
    required int maximum,
    bool confirmed = false,
    bool started = false,
  }) {
    final status = bandStatus(
      filled: filled,
      minimum: minimum,
      maximum: maximum,
      confirmed: confirmed || phase == GroupPhase.readyToReserve,
    );
    if (started && phase == GroupPhase.forming) {
      return status;
    }
    return switch (phase) {
      GroupPhase.forming || GroupPhase.readyToReserve => status,
      GroupPhase.awaitingHouse => 'Aguardando a casa',
      GroupPhase.confirmed => 'Reserva confirmada',
      GroupPhase.refused => 'A casa recusou',
      GroupPhase.awaitingPayments => 'Aguardando pagamentos',
      GroupPhase.cancelled => 'Cancelado',
    };
  }

  static String closesAtLabel(String when) => 'Prazo para confirmar: $when';

  static String cancelWindowLabel(int hours) {
    return 'Cancelar com $hours h ou mais de antecedência devolve o pagamento simulado. Menos que isso, não.';
  }
}
