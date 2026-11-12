import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/features/ranking/presentation/room_time_view.dart';

void main() {
  testWidgets('o top 10 mostra medalha, tempo e primeiro nome', (tester) async {
    await tester.pumpWidget(_app(RoomTimeBoard(lines: _board())));
    expect(find.byKey(const Key('room-time-board')), findsOneWidget);
    expect(find.text('Ranking da sala'), findsOneWidget);
    expect(find.text('Os Ninjas'), findsOneWidget);
    expect(find.text('38:12 (Restavam 21:48)'), findsOneWidget);
    expect(find.textContaining('Ana · Bruno · Caio'), findsOneWidget);
    expect(find.text('1º'), findsOneWidget);
    expect(find.text('2º'), findsOneWidget);
    expect(find.text('3º'), findsOneWidget);
    expect(find.text('10º'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('Souza'), findsNothing);
  });

  testWidgets('o perfil mostra a posição e quem não escapou', (tester) async {
    await tester.pumpWidget(_app(MyRoomTimesView(lines: _mine())));
    expect(find.byKey(const Key('my-room-times')), findsOneWidget);
    expect(find.text('Seus tempos'), findsOneWidget);
    expect(find.text('O Cofre'), findsOneWidget);
    expect(find.text('2º'), findsOneWidget);
    expect(find.text('41:05 (Restavam 18:55)'), findsOneWidget);
    expect(find.textContaining('Não escapou'), findsOneWidget);
    expect(find.text('60:00 (Restavam 00:00)'), findsOneWidget);
  });

  testWidgets('aparecer no ranking nasce ligado e o jogador desliga', (
    tester,
  ) async {
    var appears = true;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            return RoomTimeVisibilityCard(
              appears: appears,
              onChanged: (value) => setState(() => appears = value),
            );
          },
        ),
      ),
    );
    expect(find.text('Aparecer no ranking público'), findsOneWidget);
    expect(find.textContaining('O padrão é aparecer'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('room-time-visibility'))).value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('room-time-visibility')));
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('room-time-visibility'))).value,
      isFalse,
    );
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [child],
      ),
    ),
  );
}

List<RoomTimeLine> _board() {
  const names = [
    'Os Ninjas',
    'Equipe Leste',
    'Sem Pressa',
    'Grupo',
    'Os Vizinhos',
    'Chave Mestra',
    'Sala Cheia',
    'Primeira Vez',
    'Depois do Café',
    'Quase Lá',
  ];
  return [
    for (var index = 0; index < names.length; index++)
      RoomTimeLine(
        place: index + 1,
        groupName: names[index],
        elapsedSeconds: (38 + index) * 60 + 12,
        remainingSeconds: 60 * 60 - ((38 + index) * 60 + 12),
        playedOn: DateTime(2026, 11, 2),
        members: index == 0 ? const ['Ana', 'Bruno', 'Caio'] : const ['Lia'],
        escaped: true,
      ),
  ];
}

List<RoomTimeLine> _mine() {
  return [
    RoomTimeLine(
      place: 2,
      roomName: 'O Cofre',
      groupName: 'Equipe Leste',
      elapsedSeconds: 41 * 60 + 5,
      remainingSeconds: 18 * 60 + 55,
      playedOn: DateTime(2026, 11, 2),
      members: const ['Ana', 'Duda'],
      escaped: true,
    ),
    RoomTimeLine(
      roomName: 'O Labirinto',
      groupName: 'Grupo',
      elapsedSeconds: 60 * 60,
      remainingSeconds: 0,
      playedOn: DateTime(2026, 10, 18),
      members: const [],
      escaped: false,
    ),
  ];
}
