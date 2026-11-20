import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/data/room_photo_prepare.dart';

export 'package:scapematch_parceiro/features/partner/data/room_photo_prepare.dart'
    show RoomPhotoPick, RoomPhotoReadException;

/// Escolha de fotos no celular e na web. Os testes trocam o provedor.
abstract class PhotoPicker {
  Future<RoomPhotoPick> pick();
}

class FilePhotoPicker implements PhotoPicker {
  const FilePhotoPicker();

  @override
  Future<RoomPhotoPick> pick() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) {
      return const RoomPhotoPick(<Uint8List>[]);
    }
    final raw = <Uint8List>[];
    var unreadable = false;
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          raw.add(bytes);
        }
      } on Object {
        unreadable = true;
      }
    }
    final prepared = await prepareRoomPhotos(raw);
    if (!unreadable || prepared.error != null) {
      return prepared;
    }
    return RoomPhotoPick(
      prepared.photos,
      error: RoomPhotoReadException.messageText,
    );
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) {
  return const FilePhotoPicker();
});
