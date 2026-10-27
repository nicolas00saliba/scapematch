import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

/// Form state for "create a group".
///
/// [extraSpots] is the number of people still needed, not counting the
/// creator. [sizeValidation] compares that with the selected room.
class CreateGroupState {
  const CreateGroupState({
    required this.cityId,
    this.houses = const [],
    this.houseId,
    this.rooms = const [],
    this.roomId,
    this.slots = const [],
    this.slotId,
    this.extraSpots = 2,
    this.loadingOptions = false,
    this.submitting = false,
    this.failure,
  });

  final String? cityId;
  final List<EscapeHouse> houses;
  final String? houseId;
  final List<EscapeRoom> rooms;
  final String? roomId;
  final List<TimeSlot> slots;
  final String? slotId;
  final int extraSpots;
  final bool loadingOptions;
  final bool submitting;
  final CreateGroupFailureReason? failure;

  EscapeHouse? get house => _byId(houses, houseId, (house) => house.id);

  EscapeRoom? get room => _byId(rooms, roomId, (room) => room.id);

  TimeSlot? get slot => _byId(slots, slotId, (slot) => slot.id);

  GroupSizeValidation get sizeValidation {
    final capacity = room?.capacity;
    if (capacity == null) {
      return GroupSizeValidation.valid;
    }
    return GroupRules.validateGroupSize(
      extraSpots: extraSpots,
      roomCapacity: capacity,
    );
  }

  bool get hasRequiredSelections =>
      cityId != null && houseId != null && roomId != null && slotId != null;

  bool get canSubmit =>
      hasRequiredSelections &&
      sizeValidation == GroupSizeValidation.valid &&
      !submitting &&
      !loadingOptions;

  int get groupSize => 1 + extraSpots;

  CreateGroupState copyWith({
    String? cityId,
    bool clearCity = false,
    List<EscapeHouse>? houses,
    String? houseId,
    bool clearHouse = false,
    List<EscapeRoom>? rooms,
    String? roomId,
    bool clearRoom = false,
    List<TimeSlot>? slots,
    String? slotId,
    bool clearSlot = false,
    int? extraSpots,
    bool? loadingOptions,
    bool? submitting,
    CreateGroupFailureReason? failure,
    bool clearFailure = false,
  }) {
    return CreateGroupState(
      cityId: clearCity ? null : (cityId ?? this.cityId),
      houses: houses ?? this.houses,
      houseId: clearHouse ? null : (houseId ?? this.houseId),
      rooms: rooms ?? this.rooms,
      roomId: clearRoom ? null : (roomId ?? this.roomId),
      slots: slots ?? this.slots,
      slotId: clearSlot ? null : (slotId ?? this.slotId),
      extraSpots: extraSpots ?? this.extraSpots,
      loadingOptions: loadingOptions ?? this.loadingOptions,
      submitting: submitting ?? this.submitting,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

T? _byId<T>(List<T> items, String? id, String Function(T item) idOf) {
  if (id == null) {
    return null;
  }
  for (final item in items) {
    if (idOf(item) == id) {
      return item;
    }
  }
  return null;
}

/// View model of the create-group form.
///
/// The screen calls [loadInitial] when it opens. Changing the city, house,
/// or room clears the choices that depended on the previous one.
class CreateGroupViewModel extends Notifier<CreateGroupState> {
  int _generation = 0;

  @override
  CreateGroupState build() {
    return CreateGroupState(cityId: ref.read(selectedCityIdProvider));
  }

  Future<void> loadInitial() {
    return _loadHouses(state.cityId);
  }

  Future<void> selectCity(City city) async {
    ref.read(selectedCityIdProvider.notifier).select(city.id);
    await _loadHouses(city.id);
  }

  Future<void> selectHouse(String houseId) async {
    final generation = ++_generation;
    state = state.copyWith(
      houseId: houseId,
      rooms: const [],
      clearRoom: true,
      slots: const [],
      clearSlot: true,
      loadingOptions: true,
      clearFailure: true,
    );
    final rooms = await ref
        .read(catalogRepositoryProvider)
        .listRoomsByHouse(houseId);
    if (!ref.mounted || generation != _generation) {
      return;
    }
    state = state.copyWith(rooms: rooms, loadingOptions: false);
  }

  Future<void> selectRoom(String roomId) async {
    final generation = ++_generation;
    state = state.copyWith(
      roomId: roomId,
      slots: const [],
      clearSlot: true,
      loadingOptions: true,
      clearFailure: true,
    );
    final slots = await ref
        .read(catalogRepositoryProvider)
        .listSlotsByRoom(roomId);
    if (!ref.mounted || generation != _generation) {
      return;
    }
    state = state.copyWith(slots: slots, loadingOptions: false);
  }

  void selectSlot(String slotId) {
    state = state.copyWith(slotId: slotId, clearFailure: true);
  }

  void setExtraSpots(int value) {
    final spots = value.clamp(1, 12);
    state = state.copyWith(extraSpots: spots, clearFailure: true);
  }

  /// Returns the created group, or null when the form is not valid.
  Future<Group?> submit() async {
    if (!state.canSubmit) {
      return null;
    }
    state = state.copyWith(submitting: true, clearFailure: true);
    final result = await ref
        .read(groupRepositoryProvider)
        .create(
          CreateGroupRequest(
            cityId: state.cityId!,
            houseId: state.houseId!,
            roomId: state.roomId!,
            slotId: state.slotId!,
            extraSpots: state.extraSpots,
          ),
        );
    if (!ref.mounted) {
      return null;
    }
    switch (result) {
      case CreateGroupSuccess(:final group):
        state = state.copyWith(submitting: false);
        ref.invalidate(findGroupsViewModelProvider);
        return group;
      case CreateGroupFailure(:final reason):
        state = state.copyWith(submitting: false, failure: reason);
        return null;
    }
  }

  Future<void> _loadHouses(String? cityId) async {
    final generation = ++_generation;
    final extraSpots = state.extraSpots;
    state = CreateGroupState(
      cityId: cityId,
      extraSpots: extraSpots,
      loadingOptions: cityId != null,
    );
    if (cityId == null) {
      return;
    }
    final houses = await ref
        .read(catalogRepositoryProvider)
        .listHousesByCity(cityId);
    if (!ref.mounted || generation != _generation) {
      return;
    }
    state = state.copyWith(houses: houses, loadingOptions: false);
  }
}

final createGroupViewModelProvider =
    NotifierProvider.autoDispose<CreateGroupViewModel, CreateGroupState>(
      CreateGroupViewModel.new,
    );
