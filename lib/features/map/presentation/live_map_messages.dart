import 'package:scapematch/core/formatting/money_format.dart';

/// Textos do mapa ao vivo.
abstract final class LiveMapMessages {
  static const list = 'Lista';
  static const map = 'Mapa';
  static const sheetTitle = 'Grupos nesta cidade';
  static const emptySheet = 'Nenhum grupo nesta cidade.';
  static const showOnMap = 'Mostrar no mapa';
  static const attribution = '© OpenStreetMap';
  static const loading = 'Carregando o mapa...';
  static const loadError = 'Não foi possível carregar o mapa.';

  static const osmCopyright = 'https://www.openstreetmap.org/copyright';

  static String forming(int count, String city) {
    if (count == 0) {
      return 'Nenhum grupo se formando agora em $city';
    }
    if (count == 1) {
      return '1 grupo se formando agora em $city';
    }
    return '$count grupos se formando agora em $city';
  }

  static String joined(String name, String room) => '$name entrou em $room';

  /// Preço curto do pino. 10900 vira “R$ 109”.
  static String pinPrice(int priceCents) {
    final reais = (priceCents / 100).round();
    return 'R\$ $reais';
  }

  static String pinSemantics({
    required String house,
    required int formingCount,
    required int? priceCents,
  }) {
    if (formingCount > 0) {
      final noun = formingCount == 1
          ? 'grupo se formando'
          : 'grupos se formando';
      return '$house, $formingCount $noun';
    }
    if (priceCents != null) {
      return '$house, ${formatPrice(priceCents)} por pessoa';
    }
    return house;
  }
}
