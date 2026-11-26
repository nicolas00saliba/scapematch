import 'package:scapematch/features/cities/data/city_repository.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCityRepository implements CityRepository {
  SupabaseCityRepository(this._client);

  final SupabaseClient _client;

  /// Só as cidades com casa aprovada e não suspensa. O filtro é do servidor
  /// (view cities_with_active_venues): public.cities tem os 5571 municípios
  /// e a API corta a leitura em 1000 linhas.
  @override
  Future<List<City>> listCities() async {
    final rows = await _client
        .from('cities_with_active_venues')
        .select('id, name, state_code, state_name')
        .order('name');
    return [
      for (final row in rows)
        City(
          id: row['id'] as String,
          name: row['name'] as String,
          stateCode: row['state_code'] as String,
          stateName: row['state_name'] as String,
        ),
    ];
  }
}
