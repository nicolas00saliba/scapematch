import 'package:flutter/widgets.dart';

/// Stable keys shared by the screens and the widget tests.
abstract final class AppKeys {
  static const citySelector = Key('city-selector');
  static const findGroup = Key('find-group');
  static const createGroup = Key('create-group');
  static const almostFullFilter = Key('almost-full-filter');
  static const joinButton = Key('join-button');
  static const spotSummary = Key('spot-summary');
  static const extraSpotsIncrement = Key('extra-spots-increment');
  static const extraSpotsDecrement = Key('extra-spots-decrement');
  static const extraSpotsValue = Key('extra-spots-value');
  static const createSubmit = Key('create-submit');
  static const capacityError = Key('capacity-error');
  static const createFailure = Key('create-failure');
  static const retry = Key('retry');

  static Key cityOption(String id) => Key('city-option-$id');
  static Key groupCard(String id) => Key('group-card-$id');
  static Key option(String id) => Key('option-$id');
  static Key selectionField(String name) => Key('selection-$name');
}
