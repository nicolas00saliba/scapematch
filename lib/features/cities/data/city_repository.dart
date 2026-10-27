import 'package:scapematch/features/cities/domain/city.dart';

/// Where the list of cities comes from.
///
/// The screen talks only to this interface. Today the implementation reads
/// fictional data. Later it can read the same list from Supabase.
abstract class CityRepository {
  Future<List<City>> listCities();
}
