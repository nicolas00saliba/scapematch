import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Escolha de fotos no celular e na web. Os testes trocam o provedor.
abstract class PhotoPicker {
  Future<List<Uint8List>> pick();
}

class FilePhotoPicker implements PhotoPicker {
  const FilePhotoPicker();

  @override
  Future<List<Uint8List>> pick() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) {
      return const [];
    }
    final photos = <Uint8List>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        photos.add(bytes);
      }
    }
    return photos;
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) {
  return const FilePhotoPicker();
});
