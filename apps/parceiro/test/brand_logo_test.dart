import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

void main() {
  test('the partner bundle exposes the shared pin', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.getAssetVariants(
        ScapePinLoader.packagedKey(ScapeLogo.markAsset),
      ),
      isNotNull,
    );
    expect(
      manifest.getAssetVariants(
        ScapePinLoader.packagedKey(ScapeLogo.markOnDarkAsset),
      ),
      isNotNull,
    );

    final loaded = await ScapePinLoader(ScapeLogo.markAsset).readSvg();
    final shared = await rootBundle.load(
      ScapePinLoader.packagedKey(ScapeLogo.markAsset),
    );
    expect(Uint8List.sublistView(loaded), Uint8List.sublistView(shared));

    final loadedOnDark = await ScapePinLoader(ScapeLogo.markOnDarkAsset)
        .readSvg();
    final sharedOnDark = await rootBundle.load(
      ScapePinLoader.packagedKey(ScapeLogo.markOnDarkAsset),
    );
    expect(
      Uint8List.sublistView(loadedOnDark),
      Uint8List.sublistView(sharedOnDark),
    );
  });
}
