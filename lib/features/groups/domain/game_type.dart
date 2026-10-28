/// Tipo de jogo escolhido no topo da Home.
///
/// [all] é só o filtro. Um grupo concreto usa um dos outros ids.
abstract final class GameTypes {
  static const all = 'all';
  static const escapeRoom = 'escape-room';
  static const rpg = 'rpg';
  static const boardGame = 'board-game';
  static const laserTag = 'laser-tag';
  static const immersive = 'immersive';

  static const choices = <(String id, String label)>[
    (all, 'Todos'),
    (escapeRoom, 'Escape room'),
    (rpg, 'RPG'),
    (boardGame, 'Jogos de tabuleiro'),
    (laserTag, 'Laser tag'),
    (immersive, 'Imersivo'),
  ];

  static String labelOf(String id) {
    for (final choice in choices) {
      if (choice.$1 == id) {
        return choice.$2;
      }
    }
    return 'Todos';
  }

  static bool isKnown(String id) {
    for (final choice in choices) {
      if (choice.$1 == id) {
        return true;
      }
    }
    return false;
  }
}
