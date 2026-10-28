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

  static const choices = <({String id, String label, String shortLabel})>[
    (id: all, label: 'Todos', shortLabel: 'Todos'),
    (id: escapeRoom, label: 'Escape room', shortLabel: 'Escape room'),
    (id: rpg, label: 'RPG', shortLabel: 'RPG'),
    (id: boardGame, label: 'Jogos de tabuleiro', shortLabel: 'Tabuleiro'),
    (id: laserTag, label: 'Laser tag', shortLabel: 'Laser tag'),
    (id: immersive, label: 'Imersivo', shortLabel: 'Imersivo'),
  ];

  /// Nome completo, usado na folha de opções.
  static String labelOf(String id) => _choice(id).label;

  /// Nome curto do seletor fechado, para caber ao lado da cidade.
  static String shortLabelOf(String id) => _choice(id).shortLabel;

  static bool isKnown(String id) {
    for (final choice in choices) {
      if (choice.id == id) {
        return true;
      }
    }
    return false;
  }

  static ({String id, String label, String shortLabel}) _choice(String id) {
    for (final choice in choices) {
      if (choice.id == id) {
        return choice;
      }
    }
    return choices.first;
  }
}
