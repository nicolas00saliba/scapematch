import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('o relógio e o restante saem em mm:ss', () {
    expect(formatRoomClock(0), '00:00');
    expect(formatRoomClock(75), '01:15');
    expect(formatRoomClock(38 * 60 + 12), '38:12');
    expect(
      remainingSeconds(durationMinutes: 60, elapsedSeconds: 38 * 60 + 12),
      21 * 60 + 48,
    );
    expect(formatRoomTimeLine(38 * 60 + 12, 21 * 60 + 48), '38:12 (21:48)');
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
