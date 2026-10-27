import 'package:flutter/services.dart';
import 'package:scapematch/features/catalog/data/json_experience_source.dart';

/// Example [JsonExperienceSource] that reads a JSON file shipped with the app.
///
/// The file is fictional. It is not a copy of an escape-house website.
/// This is the pattern a future allowed feed would follow: load bytes the
/// app already has (or a partner file), then parse them. It does not
/// download a page.
class AssetExperienceSource extends JsonExperienceSource {
  AssetExperienceSource({
    required String houseId,
    required String assetPath,
    AssetBundle? bundle,
  }) : super(
         houseId: houseId,
         readJson: () => (bundle ?? rootBundle).loadString(assetPath),
       );

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
