import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('o tempo gasto fica em mm:ss e o restante em minutos', () {
    expect(formatRoomClock(0), '00:00');
    expect(formatRoomClock(75), '01:15');
    expect(formatRoomClock(38 * 60 + 12), '38:12');
    expect(
      remainingSeconds(durationMinutes: 60, elapsedSeconds: 38 * 60 + 12),
      21 * 60 + 48,
    );
    expect(formatRoomTimeLine(40 * 60, 20 * 60), '40:00 (Restavam 20 min)');
    expect(
      formatRoomTimeLine(38 * 60 + 12, 21 * 60 + 48),
      '38:12 (Restavam 21 min)',
    );
    expect(
      formatRoomTimeLine(41 * 60 + 5, 18 * 60 + 55),
      '41:05 (Restavam 18 min)',
    );
    expect(formatRoomTimeLine(59 * 60, 60), '59:00 (Restavam 1 min)');
    expect(formatRoomTimeLine(60 * 60, 45), '60:00 (Restavam 45 s)');
    expect(formatRoomTimeLine(60 * 60, 0), '60:00 (Restavam 0 s)');
    expect(formatRoomDate(DateTime(2026, 11, 2)), '02/11/2026');
  });

  test('medalha só nos três primeiros e o nome tem limite', () {
    expect(medalForPlace(1), RoomTimeMedal.gold);
    expect(medalForPlace(2), RoomTimeMedal.silver);
    expect(medalForPlace(3), RoomTimeMedal.bronze);
    expect(medalForPlace(4), isNull);
    expect(medalLabel(RoomTimeMedal.gold), 'Ouro');
    expect(roomTimePlaceLabel(1), '1º');
    expect(roomTimeNameError(''), isNull);
    expect(roomTimeNameOrDefault(''), roomTimeDefaultGroup);
    expect(roomTimeNameError('A'), 'O nome do grupo fica entre 2 e 40 caracteres.');
    expect(roomTimeNameError('porra'), 'Escolha outro nome para o grupo.');
    expect(roomTimeNameError('Os Ninjas'), isNull);
    expect(roomTimeNameError("Ninja's"), isNull);
    expect(firstLabel('Ana Souza'), 'Ana');
    expect(firstLabel('ana@exemplo.com'), 'Jogador');
  });
}
