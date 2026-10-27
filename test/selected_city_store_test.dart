import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/cities/data/selected_city_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('missing or blank city resolves to Curitiba', () async {
    SharedPreferences.setMockInitialValues({});
    final missing = SelectedCityStore();
    await missing.load();
    expect(missing.resolve(), SampleIds.curitiba);

    SharedPreferences.setMockInitialValues({SelectedCityStore.storageKey: ''});
    final blank = SelectedCityStore();
    await blank.load();
    expect(blank.resolve(), SampleIds.curitiba);
  });

  test('a saved city is restored', () async {
    SharedPreferences.setMockInitialValues({
      SelectedCityStore.storageKey: SampleIds.beloHorizonte,
    });
    final store = SelectedCityStore();
    await store.load();
    expect(store.resolve(), SampleIds.beloHorizonte);
  });
}
