import 'dart:typed_data';

import 'package:scapematch/features/catalog/domain/room_frame.dart';

/// Foto da casa já encaixada em cada moldura. [source] é o arquivo original,
/// para a casa poder reenquadrar nesta sessão.
class RoomPicture {
  const RoomPicture({
    required this.id,
    required this.source,
    required this.frames,
  });

  final String id;
  final Uint8List source;
  final Map<RoomFrame, Uint8List> frames;

  Uint8List? bytesFor(RoomFrame frame) {
    final exact = frames[frame];
    if (exact != null && exact.isNotEmpty) {
      return exact;
    }
    for (final bytes in frames.values) {
      if (bytes.isNotEmpty) {
        return bytes;
      }
    }
    return null;
  }
}
