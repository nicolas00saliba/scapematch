/// Tipo de jogo escolhido no topo da Home.
///
/// [all] é só o filtro. Um grupo concreto é escape room.
abstract final class GameTypes {
  static const all = 'all';
  static const escapeRoom = 'escape-room';

  static const choices = <({String id, String label, String shortLabel})>[
    (id: all, label: 'Todos', shortLabel: 'Todos'),
    (id: escapeRoom, label: 'Escape room', shortLabel: 'Escape'),
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
