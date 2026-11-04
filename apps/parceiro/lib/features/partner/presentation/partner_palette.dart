import 'package:flutter/material.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';

const agendaPalette = <int>[
  0xFF0F4C4A,
  0xFFD2642A,
  0xFF1F6F8A,
  0xFF8A4B2F,
  0xFF3E6B4F,
  0xFFB45309,
  0xFF5C4B8A,
  0xFF8A3A4B,
];

const agendaHours = <(int, int)>[(14, 0), (16, 30), (19, 0), (21, 0)];

const agendaGridStartHour = 8;
const agendaGridEndHour = 24;

Color roomColor(EscapeRoom room, int index) {
  final value = room.accent == 0
      ? agendaPalette[index % agendaPalette.length]
      : room.accent;
  return Color(value);
}

Color onRoomColor(Color color) {
  return color.computeLuminance() > 0.55
      ? const Color(0xFF1C1917)
      : Colors.white;
}
