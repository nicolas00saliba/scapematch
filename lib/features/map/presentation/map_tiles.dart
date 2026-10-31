import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tiles do mapa. OpenStreetMap, sem chave.
///
/// O cache em disco fica desligado: na web o navegador já guarda o tile,
/// e o teste troca este provider por uma imagem em memória.
final mapTileProvider = Provider<TileProvider>((ref) {
  final tiles = NetworkTileProvider(
    silenceExceptions: true,
    cachingProvider: DisabledMapCachingProvider(),
  );
  ref.onDispose(tiles.dispose);
  return tiles;
});

/// O mesmo desenho nos dois temas. [dark] não troca a URL:
/// o filtro de cor em [LiveMapView] é que faz o tema escuro.
String liveMapTileUrl({required bool dark}) {
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
