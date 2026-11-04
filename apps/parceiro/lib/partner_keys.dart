import 'package:flutter/foundation.dart';

/// Chaves do ScapeMatch Parceiro. Ficam neste app para o bundle do jogador
/// não carregar as telas da casa.
abstract final class PartnerKeys {
  static const partnerEmail = Key('partner-email');
  static const partnerPassword = Key('partner-password');
  static const partnerSubmit = Key('partner-submit');
  static const partnerLoginError = Key('partner-login-error');
  static const partnerQuickDemo = Key('partner-quick-demo');
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
  static const agendaViews = Key('agenda-views');
  static const agendaViewDay = Key('agenda-view-day');
  static const agendaViewThree = Key('agenda-view-three');
  static const agendaViewWeek = Key('agenda-view-week');
  static const agendaViewMonth = Key('agenda-view-month');
  static const agendaViewYear = Key('agenda-view-year');
  static const agendaYearGrid = Key('agenda-year-grid');
  static const agendaMonthToggle = Key('agenda-month-toggle');
  static const agendaMiniCalendar = Key('agenda-mini-calendar');
  static const agendaToday = Key('agenda-today');
  static const agendaMonthGrid = Key('agenda-month-grid');
  static Key agendaMiniDay(int year, int month, int day) =>
      Key('agenda-mini-$year-$month-$day');
  static const agendaSaveSession = Key('agenda-save-session');
  static const agendaSaveRoom = Key('agenda-save-room');
  static const agendaRoomName = Key('agenda-room-name');
  static const roomForm = Key('room-form');
  static const roomStory = Key('room-story');
  static const roomAddPhotos = Key('room-add-photos');
  static const roomExpand = Key('room-expand');
  static const roomFramePreview = Key('room-frame-preview');
  static const roomSimulated = Key('room-simulated');
  static Key roomCategory(String name) => Key('room-category-$name');
  static Key roomFrame(String name) => Key('room-frame-$name');
  static const agendaCancel = Key('agenda-cancel');
  static const agendaSheet = Key('agenda-sheet');
  static const agendaUpcoming = Key('agenda-upcoming');
  static const agendaDone = Key('agenda-done');
  static const agendaCancelled = Key('agenda-cancelled');
  static Key agendaBlock(String id) => Key('agenda-block-$id');
  static Key agendaTime(String label) => Key('agenda-time-$label');
}
