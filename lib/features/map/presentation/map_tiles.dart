import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tiles do mapa, sem chave.
///
/// No celular o cache embutido guarda o tile. Na web esse cache não grava
/// disco: o navegador já guarda a resposta, e um pedido antigo é cancelado
/// quando o tile sai da tela. O teste troca este provider por memória.
final mapTileProvider = Provider<TileProvider>((ref) {
  final tiles = NetworkTileProvider(silenceExceptions: true);
  ref.onDispose(tiles.dispose);
  return tiles;
});

/// Os dois temas usam o mesmo tile do OpenStreetMap, sem chave.
///
/// O claro não leva filtro: o desenho padrão já é claro. O CARTO Voyager
/// público passou a exigir chave. O escuro continua com o filtro que já
/// escurece este tile.
String liveMapTileUrl({required bool dark}) {
  const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  return dark ? osm : osm;
}
