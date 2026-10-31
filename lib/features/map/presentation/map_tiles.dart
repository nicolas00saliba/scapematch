import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tiles do mapa. OpenStreetMap, sem chave.
///
/// No celular o cache embutido guarda o tile. Na web esse cache não grava
/// disco: o navegador já guarda a resposta, e um pedido antigo é cancelado
/// quando o tile sai da tela. O teste troca este provider por memória.
final mapTileProvider = Provider<TileProvider>((ref) {
  final tiles = NetworkTileProvider(silenceExceptions: true);
  ref.onDispose(tiles.dispose);
  return tiles;
});

/// O mesmo desenho nos dois temas. [dark] não troca a URL:
/// o filtro de cor em [LiveMapView] é que faz o tema escuro.
String liveMapTileUrl({required bool dark}) {
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
