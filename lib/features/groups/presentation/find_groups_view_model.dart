import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/providers/repositories.dart';

/// Whether the list is limited to groups that are almost full.
class AlmostFullFilterController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) {
    state = value;
  }
}

final almostFullOnlyProvider =
    NotifierProvider<AlmostFullFilterController, bool>(
      AlmostFullFilterController.new,
    );

/// View model of the "find a group" screen.
///
/// It watches the selected city and the filter, then asks the repository
/// for the matching groups. The widget only draws whatever this returns.
class FindGroupsViewModel extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() {
    final cityId = ref.watch(selectedCityIdProvider);
    final almostFullOnly = ref.watch(almostFullOnlyProvider);
    if (cityId == null) {
      return Future.value(const []);
    }
    return ref
        .watch(groupRepositoryProvider)
        .listByCity(cityId, almostFullOnly: almostFullOnly);
  }
}

final findGroupsViewModelProvider =
    AsyncNotifierProvider.autoDispose<FindGroupsViewModel, List<Group>>(
      FindGroupsViewModel.new,
    );
