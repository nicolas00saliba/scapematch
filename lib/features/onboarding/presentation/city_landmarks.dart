import 'package:flutter/material.dart';
import 'package:scapematch/core/data/sample_ids.dart';

/// Ponto turístico da introdução, um por cidade do catálogo.
///
/// [alignment] é o ponto focal no [BoxFit.cover]. O y negativo segura o
/// assunto na metade de cima, acima do título e do cartão da cidade.
class CityLandmark {
  const CityLandmark({
    required this.cityId,
    required this.name,
    required this.asset,
    required this.alignment,
  });

  final String cityId;
  final String name;
  final String asset;
  final Alignment alignment;
}

const cityLandmarks = <CityLandmark>[
  CityLandmark(
    cityId: SampleIds.curitiba,
    name: 'Jardim Botânico',
    asset: 'assets/images/landmarks/curitiba.jpg',
    alignment: Alignment(0, -0.9),
  ),
  CityLandmark(
    cityId: SampleIds.saoPaulo,
    name: 'MASP',
    asset: 'assets/images/landmarks/sao-paulo.jpg',
    alignment: Alignment(-0.15, -0.85),
  ),
  CityLandmark(
    cityId: SampleIds.rioDeJaneiro,
    name: 'Cristo Redentor',
    asset: 'assets/images/landmarks/rio.jpg',
    alignment: Alignment(0, -1),
  ),
  CityLandmark(
    cityId: SampleIds.beloHorizonte,
    name: 'Igreja da Pampulha',
    asset: 'assets/images/landmarks/belo-horizonte.jpg',
    alignment: Alignment(0, -1),
  ),
  CityLandmark(
    cityId: SampleIds.portoAlegre,
    name: 'Orla do Guaíba',
    asset: 'assets/images/landmarks/porto-alegre.jpg',
    alignment: Alignment(0.15, -1),
  ),
];

/// Cidade fora do catálogo usa Curitiba, para a foto nunca ficar vazia.
CityLandmark landmarkFor(String? cityId) {
  for (final landmark in cityLandmarks) {
    if (landmark.cityId == cityId) {
      return landmark;
    }
  }
  return cityLandmarks.first;
}
