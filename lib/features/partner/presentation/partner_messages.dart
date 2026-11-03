import 'package:dominio/dominio.dart';

/// Textos do ScapeMatch Parceiro.
abstract final class PartnerMessages {
  static const title = 'Parceiro';
  static const loginTitle = 'Entrar como casa';
  static const loginBody =
      'Conta de exemplo. O saldo é o mesmo livro do app do jogador, nesta sessão.';
  static const emailHint =
      'Casa de exemplo: xv@scapematch.exemplo. Senha: demo.';
  static const badLogin = 'E-mail ou senha não conferem neste exemplo.';
  static const openPlayerApp = 'App do jogador';
  static const signOut = 'Sair';
  static const balance = 'Saldo';
  static const reservations = 'Reservas';
  static const rooms = 'Salas';
  static const balanceTitle = 'Saldo da casa';
  static const balanceBody =
      'O líquido é o que fica com a casa depois da comissão. O valor reservado só entra quando o grupo fecha.';
  static const netLabel = 'Líquido';
  static const grossLabel = 'Bruto';
  static const commissionLabel = 'Comissão';
  static const reservedLabel = 'Reservado';
  static const reservedBody =
      'Ainda não entrou no saldo. Se o grupo não fechar, o valor é liberado e nada é cobrado.';
  static const statement = 'Extrato';
  static const statementEmpty =
      'Nenhuma captura ainda. Quando um grupo fecha, o valor aparece aqui.';
  static const capture = 'Captura';
  static const refund = 'Estorno';
  static const reservationsTitle = 'Reservas e grupos';
  static const roomsTitle = 'Salas, horários e preços';
  static const roomsBody =
      'O preço e os horários novos valem nesta sessão, também no app do jogador.';
  static const priceLabel = 'Preço por pessoa (R\$)';
  static const savePrice = 'Salvar preço';
  static const priceSaved = 'Preço atualizado nesta sessão.';
  static const addSlot = 'Novo horário';
  static const slotOpened = 'Horário aberto nesta sessão.';
  static const markAbsence = 'Marcar falta';
  static const pastSlots = 'horários já encerrados';
  static const noFutureSlots = 'Nenhum horário futuro nesta sala.';
  static const cancelled = 'Cancelado';
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
}
