import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Tile de um pixel. O teste do mapa não fala com a rede.
class MemoryTileProvider extends TileProvider {
  MemoryTileProvider() : super();

  static final Uint8List _bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  static final ImageProvider _image = MemoryImage(_bytes);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _image;
  }
}
