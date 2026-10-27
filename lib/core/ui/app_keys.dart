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
  static const myGroups = Key('my-groups');
  static const confirmAttendance = Key('confirm-attendance');
  static const leaveGroup = Key('leave-group');
  static const deleteGroup = Key('delete-group');
  static const editGroup = Key('edit-group');
  static const shareGroup = Key('share-group');
  static const refundWarning = Key('refund-warning');
  static const dialogConfirm = Key('dialog-confirm');
  static const confirmedCount = Key('confirmed-count');
  static const countdown = Key('countdown');
  static const priceLabel = Key('price-label');
  static const refundStatus = Key('refund-status');
  static const editSpotsIncrement = Key('edit-spots-increment');
  static const editSpotsDecrement = Key('edit-spots-decrement');
  static const editSpotsValue = Key('edit-spots-value');
  static const editNote = Key('edit-note');
  static const editSave = Key('edit-save');
  static const editError = Key('edit-error');
  static const myGroupsUpcoming = Key('my-groups-upcoming');
  static const myGroupsPast = Key('my-groups-past');
  static const myGroupsCancelled = Key('my-groups-cancelled');
  static const sessionStarted = Key('session-started');
  static const groupNote = Key('group-note');

  static Key removeMember(String id) => Key('remove-member-$id');

  static Key cityOption(String id) => Key('city-option-$id');
  static Key groupCard(String id) => Key('group-card-$id');
  static Key option(String id) => Key('option-$id');
  static Key selectionField(String name) => Key('selection-$name');
}
