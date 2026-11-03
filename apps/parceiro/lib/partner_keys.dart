import 'package:flutter/foundation.dart';

/// Chaves do ScapeMatch Parceiro. Ficam neste app para o bundle do jogador
/// não carregar as telas da casa.
abstract final class PartnerKeys {
  static const partnerEmail = Key('partner-email');
  static const partnerPassword = Key('partner-password');
  static const partnerSubmit = Key('partner-submit');
  static const partnerLoginError = Key('partner-login-error');
  static const partnerSignOut = Key('partner-sign-out');
  static const partnerHouseName = Key('partner-house-name');
  static const partnerNet = Key('partner-net');
  static const partnerGross = Key('partner-gross');
  static const partnerCommission = Key('partner-commission');
  static const partnerReserved = Key('partner-reserved');
  static Key partnerPrice(String roomId) => Key('partner-price-$roomId');
  static Key partnerSavePrice(String roomId) =>
      Key('partner-save-price-$roomId');
  static Key partnerAddSlot(String roomId) => Key('partner-add-slot-$roomId');
  static Key partnerAbsence(String groupId, String playerId) =>
      Key('partner-absence-$groupId-$playerId');
  static Key partnerAbsenceStanding(String groupId, String playerId) =>
      Key('partner-absence-standing-$groupId-$playerId');
  static const agendaCalendar = Key('agenda-calendar');
  static const agendaList = Key('agenda-list');
  static const agendaAdd = Key('agenda-add');
  static const agendaRooms = Key('agenda-rooms');
  static const agendaAddRoom = Key('agenda-add-room');
  static const agendaSaveSession = Key('agenda-save-session');
  static const agendaSaveRoom = Key('agenda-save-room');
  static const agendaRoomName = Key('agenda-room-name');
  static const agendaCancel = Key('agenda-cancel');
  static const agendaSheet = Key('agenda-sheet');
  static const agendaUpcoming = Key('agenda-upcoming');
  static const agendaDone = Key('agenda-done');
  static const agendaCancelled = Key('agenda-cancelled');
  static Key agendaBlock(String id) => Key('agenda-block-$id');
  static Key agendaTime(String label) => Key('agenda-time-$label');
}
