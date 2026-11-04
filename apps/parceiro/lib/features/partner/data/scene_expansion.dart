import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';

/// Porta da expansão de cenário. A tela pede o preenchimento das faixas;
/// quem pinta é um provedor.
///
/// Sem [sceneServiceUrl], vale a simulação neste aparelho. O provedor real
/// não recebe chave aqui: o Parceiro é um site público, e a chave ficaria
/// no navegador. Quem chama a Stability é um serviço no servidor
/// (por exemplo uma função do Supabase) apontado por `SCAPEMATCH_SCENE_URL`.
/// Esse serviço guarda `STABILITY_API_KEY` e faz
/// `POST https://api.stability.ai/v2beta/stable-image/edit/outpaint`
/// com a imagem e as faixas `left`, `right`, `up` e `down`.
abstract class SceneExpansionProvider {
  String get id;
  bool get isSimulation;

  Future<Uint8List> expand({
    required ui.Image source,
    required RoomFrame frame,
  });
}

class SimulatedSceneExpansion implements SceneExpansionProvider {
  const SimulatedSceneExpansion();

  @override
  String get id => 'simulated';

  @override
  bool get isSimulation => true;

  @override
  Future<Uint8List> expand({
    required ui.Image source,
    required RoomFrame frame,
  }) {
    return simulateSceneFill(source: source, frame: frame);
  }
}

/// Chama o serviço de expansão. A URL não é segredo; a chave fica lá.
class RemoteSceneExpansion implements SceneExpansionProvider {
  RemoteSceneExpansion({
    required this.endpoint,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final http.Client _client;

  @override
  String get id => 'remote';

  @override
  bool get isSimulation => false;

  @override
  Future<Uint8List> expand({
    required ui.Image source,
    required RoomFrame frame,
  }) async {
    final scale = containScale(
      imageWidth: source.width,
      imageHeight: source.height,
      frameWidth: frame.width,
      frameHeight: frame.height,
    );
    final rect = placedRect(
      imageWidth: source.width,
      imageHeight: source.height,
      frameWidth: frame.width,
      frameHeight: frame.height,
      placement: FramePlacement(scale: scale),
    );
    final left = rect.left.round().clamp(0, frame.width - 1);
    final top = rect.top.round().clamp(0, frame.height - 1);
    final contentW = rect.width.round().clamp(1, frame.width - left);
    final contentH = rect.height.round().clamp(1, frame.height - top);
    final right = frame.width - left - contentW;
    final bottom = frame.height - top - contentH;
    final content = await renderImageBox(
      source: source,
      width: contentW,
      height: contentH,
    );
    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers['accept'] = 'image/*'
      ..fields['left'] = '$left'
      ..fields['right'] = '$right'
      ..fields['up'] = '$top'
      ..fields['down'] = '$bottom'
      ..files.add(
        http.MultipartFile.fromBytes('image', content, filename: 'sala.png'),
      );
    final sent = await _client.send(request);
    final body = await sent.stream.toBytes();
    if (sent.statusCode < 200 || sent.statusCode >= 300) {
      final text = utf8.decode(body, allowMalformed: true);
      throw SceneExpansionException(
        'A expansão não respondeu (${sent.statusCode}). $text',
      );
    }
    return body;
  }
}

class SceneExpansionException implements Exception {
  SceneExpansionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Endereço do serviço que guarda a chave. Vazio enquanto a simulação vale.
const sceneServiceUrl = String.fromEnvironment('SCAPEMATCH_SCENE_URL');

final sceneExpansionProvider = Provider<SceneExpansionProvider>((ref) {
  if (sceneServiceUrl.isEmpty) {
    return const SimulatedSceneExpansion();
  }
  return RemoteSceneExpansion(endpoint: sceneServiceUrl);
});
