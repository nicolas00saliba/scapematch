import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/providers/repositories.dart';

final citiesProvider = FutureProvider<List<City>>((ref) {
  return ref.watch(cityRepositoryProvider).listCities();
});
