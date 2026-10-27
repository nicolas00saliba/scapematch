import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/features/catalog/data/catalog_repository.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/cities/data/city_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';

/// One in-memory database for the whole session.
///
/// The three repositories below share it, so a group created on one screen
/// shows up on the others. Tests can override any of these providers.
final fakeDatabaseProvider = Provider<FakeDatabase>((ref) {
  return buildSampleDatabase();
});

final cityRepositoryProvider = Provider<CityRepository>((ref) {
  return FakeCityRepository(ref.watch(fakeDatabaseProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return FakeCatalogRepository(ref.watch(fakeDatabaseProvider));
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FakeGroupRepository(ref.watch(fakeDatabaseProvider));
});
