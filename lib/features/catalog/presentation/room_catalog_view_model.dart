import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/providers/repositories.dart';

/// Salas da cidade selecionada, para os carrosséis da Home.
class RoomCatalogViewModel extends AsyncNotifier<List<RoomListing>> {
  @override
  Future<List<RoomListing>> build() {
    final cityId = ref.watch(selectedCityIdProvider);
    return ref.watch(catalogRepositoryProvider).listRoomsByCity(cityId);
  }
}

final roomCatalogViewModelProvider =
    AsyncNotifierProvider.autoDispose<RoomCatalogViewModel, List<RoomListing>>(
      RoomCatalogViewModel.new,
    );
