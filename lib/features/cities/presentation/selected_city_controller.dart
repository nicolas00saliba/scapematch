import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The city currently chosen in the big selector.
///
/// It starts empty on purpose. The app must not assume Curitiba, or any
/// other city, until the person picks one.
class SelectedCityController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String cityId) {
    state = cityId;
  }
}

final selectedCityIdProvider =
    NotifierProvider<SelectedCityController, String?>(
      SelectedCityController.new,
    );
