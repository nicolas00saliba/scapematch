import 'package:scapematch/core/data/sample_ids.dart';

/// Ponto turístico da introdução, um por cidade do catálogo.
class CityLandmark {
  const CityLandmark({
    required this.cityId,
    required this.name,
    required this.asset,
  });

  final String cityId;
  final String name;
  final String asset;
}

const cityLandmarks = <CityLandmark>[
  CityLandmark(
    cityId: SampleIds.curitiba,
    name: 'Jardim Botânico',
    asset: 'assets/images/landmarks/curitiba.jpg',
  ),
  CityLandmark(
    cityId: SampleIds.saoPaulo,
    name: 'MASP',
    asset: 'assets/images/landmarks/sao-paulo.jpg',
  ),
  CityLandmark(
    cityId: SampleIds.rioDeJaneiro,
    name: 'Cristo Redentor',
    asset: 'assets/images/landmarks/rio.jpg',
  ),
  CityLandmark(
    cityId: SampleIds.beloHorizonte,
    name: 'Igreja da Pampulha',
    asset: 'assets/images/landmarks/belo-horizonte.jpg',
  ),
  CityLandmark(
    cityId: SampleIds.portoAlegre,
    name: 'Usina do Gasômetro',
    asset: 'assets/images/landmarks/porto-alegre.jpg',
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
