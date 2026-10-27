import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/features/cities/data/city_repository.dart';
import 'package:scapematch/features/cities/domain/city.dart';

class FakeCityRepository implements CityRepository {
  FakeCityRepository(
    this._database, {
    this.latency = const Duration(milliseconds: 280),
  });

  final FakeDatabase _database;
  final Duration latency;

  @override
  Future<List<City>> listCities() async {
    await _pause();
    final cities = [..._database.cities]
      ..sort((a, b) => a.name.compareTo(b.name));
    return cities;
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}
