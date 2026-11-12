import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compara o golden com folga de 2%. O texto rasterizado muda alguns pixels
/// entre máquinas Linux com a mesma versão do Flutter.
class FolgaGolden extends LocalFileComparator {
  FolgaGolden(super.basedir, {this.folga = 0.02});

  final double folga;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= folga) {
      result.dispose();
      return true;
    }
    final erro = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(erro);
  }
}

void usarFolgaGolden() {
  final atual = goldenFileComparator;
  if (atual is LocalFileComparator && atual is! FolgaGolden) {
    goldenFileComparator = FolgaGolden(atual.basedir);
  }
}
