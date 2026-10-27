import 'package:flutter/services.dart';
import 'package:scapematch/features/catalog/data/json_experience_source.dart';
import 'package:scapematch/features/catalog/domain/experience_source.dart';

/// Example source that reads a JSON file shipped with the app.
///
/// The file is fictional. It is not a copy of an escape-house website.
/// This is the pattern a future allowed feed would follow: load bytes the
/// app already has (or a partner file), then parse them. It does not
/// download a page.
class AssetExperienceSource implements ExperienceSource {
  AssetExperienceSource({
    required this.houseId,
    required String assetPath,
    AssetBundle? bundle,
  }) : _inner = JsonExperienceSource(
         houseId: houseId,
         readJson: () => (bundle ?? rootBundle).loadString(assetPath),
       );

  final JsonExperienceSource _inner;

  @override
  final String houseId;

  @override
  Future<ExperienceOffering> fetchOffering() => _inner.fetchOffering();

  static const exampleAssetPath = 'assets/experience/example_house.json';
  static const exampleHouseId = 'example-house';

  factory AssetExperienceSource.example({AssetBundle? bundle}) {
    return AssetExperienceSource(
      houseId: exampleHouseId,
      assetPath: exampleAssetPath,
      bundle: bundle,
    );
  }
}
