import 'package:dominio/dominio.dart';

/// Textos do EscapeMatch Parceiro.
abstract final class PartnerMessages {
  static const title = 'Parceiro';
  static const loginTitle = 'Entrar como casa';
  static const loginBody =
      'Conta de exemplo, separada do app do jogador. O saldo é o livro de exemplo desta casa.';
  static const loginBodyLive =
      'Entre com a conta da casa. A senha é a do EscapeMatch, não um atalho fixo.';
  static const signUp = 'Criar conta da casa';
  static const badLogin = 'E-mail ou senha não conferem neste exemplo.';
  static const badLoginLive = 'E-mail ou senha não conferem.';
  static const awaitingTitle = 'Aguardando aprovação';
  static const awaitingBody =
      'Recebemos o cadastro da casa. O painel abre quando um admin aprovar.';
  static const rejectedTitle = 'Casa não aprovada';
  static const rejectedBody =
      'Este cadastro foi recusado. Você pode enviar outra casa.';
  static const refresh = 'Atualizar';
  static const sendVenue = 'Enviar casa';
  static const anotherVenue = 'Enviar outra casa';
  static const adminTitle = 'Casas para aprovar';
  static const adminEmpty = 'Nenhuma casa pendente.';
  static const approve = 'Aprovar';
  static const reject = 'Recusar';
  static const openHouse = 'Abrir minha casa';
  static const backToAdmin = 'Voltar às aprovações';
  static const signOut = 'Sair';
  static const balance = 'Saldo';
  static const reservations = 'Reservas';
  static const invoices = 'Notas fiscais';
  static const reviews = 'Avaliações';
  static const ranking = 'Ranking';
  static const rooms = 'Salas';
  static const agenda = 'Agenda';
  static const agendaList = 'Lista';
  static const upcoming = 'Próximas';
  static const done = 'Realizadas';
  static const cancelledTab = 'Canceladas';
  static const addSession = 'Nova sessão';
  static const manageRooms = 'Gerir salas';
  static const newRoom = 'Nova sala';
  static const saveRoom = 'Salvar sala';
  static const editRoom = 'Editar sala';
  static const roomName = 'Nome';
  static const roomDuration = 'Duração (minutos)';
  static const roomMinimum = 'Mínimo de pessoas';
  static const roomMaximum = 'Máximo de pessoas';
  static const roomColor = 'Cor na agenda';
  static const roomStory = 'História da sala';
  static const roomStoryHint = 'Uma frase que o jogador lê na ficha.';
  static const roomCategory = 'Tema';
  static const roomPlayers = 'Faixa de jogadores';
  static const roomPhotos = 'Fotos';
  static const roomPhotosBody =
      'A capa é a primeira foto. Cada moldura é a proporção real do card, da capa e da galeria.';
  static const roomAddPhotos = 'Enviar fotos';
  static const roomCover = 'Capa';
  static const roomMakeCover = 'Usar como capa';
  static const roomRemovePhoto = 'Remover';
  static const roomMoveBack = 'Mover para trás';
  static const roomMoveForward = 'Mover para frente';
  static const roomExpand = 'Expandir cenário com IA';
  static const roomSimulated = 'Simulação';
  static const roomZoom = 'Zoom';
  static const roomFrames = 'Molduras';
  static const roomPhotoUnread = 'Não foi possível ler essa foto.';
  static const back = 'Voltar';
  static const today = 'Hoje';
  static const viewDay = 'Dia';
  static const viewThreeDays = '3 dias';
  static const viewWeek = 'Semana';
  static const viewMonth = 'Mês';
  static const viewYear = 'Ano';
  static const agendaViews = 'Visão';
  static const calendarRooms = 'Cores das salas';
  static const free = 'Livre';
  static const noReservations = 'Nada nesta lista.';
  static const nobodyYet = 'Ninguém entrou ainda.';
  static const openSession = 'Abrir sessão';
  static const cancelSession = 'Cancelar sessão';
  static const sessionSaved = 'Sessão aberta nesta sessão.';
  static const roomSaved = 'Sala gravada nesta sessão.';
  static const noSessions = 'Nada neste dia.';
  static const noShows = 'Faltas';
  static const balanceTitle = 'Saldo da casa';
  static const balanceBody =
      'O líquido é o que fica com a casa depois da comissão. O valor reservado só entra quando o grupo confirma.';
  static const netLabel = 'Líquido';
  static const grossLabel = 'Bruto';
  static const commissionLabel = 'Comissão';
  static const reservedLabel = 'Reservado';
  static const reservedBody =
      'Ainda não entrou no saldo. Se o grupo não confirmar, o valor é liberado e nada é cobrado.';
  static const statement = 'Extrato';
  static const statementEmpty =
      'Nenhuma captura ainda. Quando um grupo confirma, o valor aparece aqui.';
  static const capture = 'Captura';
  static const refund = 'Estorno';
  static const reservationsTitle = 'Reservas e grupos';
  static const roomsTitle = 'Salas, horários e preços';
  static const roomsBody =
      'Uma sala nova, o preço e os horários valem nesta sessão, também no app do jogador.';
  static const priceLabel = 'Preço por pessoa (R\$)';
  static const savePrice = 'Salvar preço';
  static const priceSaved = 'Preço atualizado nesta sessão.';
  static const addSlot = 'Novo horário';
  static const slotOpened = 'Horário aberto nesta sessão.';
  static const removeSlotTitle = 'Remover horário?';
  static const removeSlotConfirm = 'Remover';
  static const removeSlotCancel = 'Cancelar';
  static const removeSlotTooltip = 'Remover horário';
  static const slotRemoved = 'Horário removido.';
  static const slotHasReservation = 'Esse horário já tem reserva';
  static const slotRemoveFailed = 'Não foi possível remover o horário.';

  static String removeSlotBody(String when) {
    return 'Remover $when? O horário sai da busca, da sala e da reserva.';
  }

  static const markAbsence = 'Marcar falta';
  static const confirmAttendance = 'Confirmar comparecimento';
  static const attended = 'Compareceu';
  static const pastSlots = 'horários já encerrados';
  static const noFutureSlots = 'Nenhum horário futuro nesta sala.';
  static const openGroup = 'Aberto';
  static const confirmedGroup = 'Confirmado';
  static const fullGroup = 'Lotado';
  static const closedGroup = 'Lotado';
  static const cancelled = 'Cancelado';

  static String reservedOf(int reserved, int total) {
    if (reserved <= 0) {
      return 'Ninguém reservou ainda';
    }
    return '$reserved de $total reservaram';
  }

  static String paidOf(int paid, int total) {
    if (paid <= 0) {
      return 'Ninguém pagou ainda';
    }
    if (paid == 1) {
      return '1 de $total pagou';
    }
    return '$paid de $total pagaram';
  }

  static const signupVenue = 'Cadastrar casa';
  static const signupTerms = 'Termos da casa';
  static const adminQueue = 'Aprovar casas';
  static const checkVenue = 'Verificar';
  static const venueName = 'Nome da casa';
  static const venueCity = 'Cidade';
  static const venuePostalCode = 'CEP';
  static const venueNumber = 'Número';
  static const venueDocument = 'CPF ou CNPJ';
  static const signupIntro =
      'O documento repetido não entra. CEP e número iguais, ou nome parecido na mesma cidade, avisam e deixam enviar como possível duplicata.';
  static const duplicateTitle = 'Possível duplicata';
  static const documentBlockedTitle = 'Documento já cadastrado';
  static const documentBlockedHidden =
      'Este documento já está em análise. O cadastro não segue.';
  static const duplicateHint =
      'Você pode enviar assim mesmo, marcado como possível duplicata, ou dizer que esta casa é sua.';
  static const submitAnyway = 'Enviar mesmo assim';
  static const claimTitle = 'Esta casa é minha?';
  static const claimBody =
      'O pedido vai para o admin. Documento, telefone e casas pendentes de outras pessoas não aparecem aqui.';
  static const claimNote = 'Por que a casa é sua?';
  static const claimNoteHint = 'Sem documento e sem telefone.';
  static const sendClaim = 'Pedir reivindicação';
  static const claimSent =
      'Pedido enviado. O admin decide se a casa passa para você.';
  static const signupSent = 'Cadastro enviado para análise.';
  static const signupMarked = 'Ele ficou marcado como possível duplicata.';
  static const pendingVenue = 'Casa pendente';
  static const similarVenues = 'Parecidas';
  static const claimsTitle = 'Reivindicações';
  static const noPendingVenues = 'Nenhuma casa pendente.';
  static const noSimilarVenues = 'Nenhuma casa aprovada parecida.';
  static const noClaims = 'Nenhuma reivindicação ligada a este cadastro.';
  static const approveVenue = 'Aprovar';
  static const rejectVenue = 'Recusar';
  static const mergeVenue = 'Mesclar';
  static const approveClaim = 'Aprovar reivindicação';
  static const rejectClaim = 'Recusar reivindicação';
  static const approvalIntro =
      'A casa pendente fica ao lado das parecidas e das reivindicações. Aprovar, recusar ou mesclar.';
  static const possibleDuplicateOf = 'Possível duplicata de';
  static const documentLabel = 'Documento';
  static const invalidVenue =
      'Preencha nome, cidade, CEP com 8 dígitos, número e um CPF ou CNPJ.';

  static String documentBlockedNamed(String name) =>
      'Já existe uma casa aprovada com este documento: $name. O cadastro não segue.';

  static String addressWarning(String name) =>
      'O CEP e o número coincidem com $name.';

  static String nameWarning(String name) =>
      'O nome parece com $name nesta cidade.';

  static const couldNotOpen = 'Não foi possível abrir a casa.';
  static const retry = 'Tentar de novo';

  static String absenceLine(int count, AbsenceStanding standing) {
    final times = count == 1 ? '1 falta' : '$count faltas';
    return switch (standing) {
      AbsenceStanding.warned => '$times · aviso',
      AbsenceStanding.blocked => '$times · bloqueio temporário',
      AbsenceStanding.clear => times,
    };
  }

  static String perPerson(String price) => '$price por pessoa';

  static const withdrawalsTitle = 'Saldo e saques';
  static const withdrawalsBody =
      'O saldo disponível já está na subconta da casa. O saque vai para uma conta com o mesmo CPF ou CNPJ.';
  static const withdrawalPixNotice =
      'Os saques saem por Pix. Em conta CNPJ, o Asaas dá 30 Pix grátis por mês.';
  static const availableLabel = 'Disponível para saque';
  static const receivableLabel = 'A receber';
  static const receivableEmpty = 'Nada a receber no momento.';
  static const withdrawalHistory = 'Histórico de saques';
  static const withdrawalEmpty = 'Nenhum saque ainda.';
  static const withdrawalAmount = 'Valor do saque';
  static const withdrawalSubmit = 'Sacar';
  static const withdrawalBank = 'Conta de saque';
  static const withdrawalNoBank = 'Nenhuma conta cadastrada.';
  static const withdrawalChangeBank = 'Alterar conta';
  static const withdrawalSaveBank = 'Salvar conta';
  static const withdrawalPix = 'Chave Pix';
  static const withdrawalBankAccount = 'Conta bancária';
  static const withdrawalBankPix = 'Esta conta recebe o saque por Pix.';
  static const withdrawalOwner = 'Nome do titular';
  static const withdrawalDocument = 'CPF ou CNPJ do titular';
  static const withdrawalAuto = 'Saque automático';
  static const withdrawalAutoSwitch = 'Sacar automaticamente';
  static const withdrawalAll = 'Sacar tudo';
  static const withdrawalRetry = 'Tentar de novo';
  static const withdrawalAutoBody =
      'Uma vez por semana, no dia escolhido, o saldo disponível segue por Pix.';
  static const withdrawalWeekly = 'Semanal';
  static const withdrawalMinimum = 'Valor mínimo';
  static const withdrawalSaveSchedule = 'Salvar automático';
  static const withdrawalStaff =
      'Só o dono ou um admin da casa pode sacar. A equipe não movimenta este saldo.';
  static const withdrawalBlocked =
      'Os saques ficam bloqueados por 24 horas depois da troca da conta. O dono recebe um e-mail.';
  static const withdrawalPassword = 'Senha da casa';
  static const withdrawalTotp = 'Código do autenticador';
  static const withdrawalConfirm = 'Confirmar';
  static const withdrawalAmountInvalid = 'Informe o valor do saque.';
  static const withdrawalReauth = 'Confirme que é você';
  static const withdrawalReceipt = 'Comprovante';
  static const withdrawalPending = 'Pendente';
  static const withdrawalDone = 'Concluído';
  static const withdrawalFailed = 'Falhou';
  static const withdrawalCancelled = 'Cancelado';
  static const withdrawalManual = 'Manual';
  static const withdrawalAutomatic = 'Automático';
  static const documentsTitle = 'Documentos da subconta';
  static const documentsBody =
      'O Asaas só libera o saque com os documentos aprovados.';
  static const documentsApproved = 'Documentos e conta aprovados';
  static const documentsPending = 'Aguardando aprovação do Asaas';
  static const documentsHosted =
      'O envio é no site do Asaas. O EscapeMatch não guarda o arquivo.';
  static const documentsOpen = 'Enviar no site do Asaas';
  static const documentsUnsafe =
      'O Asaas pediu um link que não reconhecemos. Atualize a tela.';
  static const documentsUpload =
      'Este documento não tem link do Asaas. O arquivo segue direto e não fica aqui.';
  static const documentsSend = 'Enviar arquivo';
  static const documentsRefresh = 'Atualizar status';
  static const documentsUnavailable =
      'Não foi possível consultar os documentos.';
  static const documentsWait =
      'Conta nova: espere uns 15 segundos e atualize. O Asaas ainda está definindo o que é obrigatório.';
  static const documentsBlockWithdraw =
      'O saque libera quando o Asaas aprovar os documentos e a conta.';
  static const documentsFile = 'Escolha um PDF, JPG ou PNG.';

  static String documentStatus(String status) {
    return switch (status) {
      'APPROVED' => 'Aprovado',
      'AWAITING_APPROVAL' => 'Em análise',
      'PENDING' => 'Pendente',
      'REJECTED' => 'Recusado',
      'NOT_SENT' => 'Não enviado',
      _ => 'Indisponível',
    };
  }
}
