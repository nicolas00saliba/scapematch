import 'package:dominio/src/payment_exception.dart';

/// Quanto antes do início o host ainda pode excluir o grupo.
const deleteLead = Duration(hours: 2);

/// O host exclui até 2 horas antes. No instante exato ainda pode.
bool canDeleteGroup({
  required DateTime startsAt,
  required DateTime now,
  Duration lead = deleteLead,
}) {
  return !now.isAfter(startsAt.subtract(lead));
}

/// Fechar com menos gente exige o mínimo da sala e gente sentada abaixo do Z.
bool canCloseWithFewer({
  required int seated,
  required int roomMinimum,
  required int planned,
}) {
  if (seated < roomMinimum) {
    return false;
  }
  return seated < planned;
}

void requireCloseWithFewer({
  required int seated,
  required int roomMinimum,
  required int planned,
}) {
  if (seated < roomMinimum) {
    throw PaymentException('Mínimo da sala: $roomMinimum');
  }
  if (seated >= planned) {
    throw PaymentException('O grupo já está no tamanho planejado.');
  }
  if (seated < 1) {
    throw PaymentException('Não há pessoas para fechar o grupo.');
  }
}
