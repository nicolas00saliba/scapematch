/// Caderno que `my_passport` devolve. A flag desligada chega como
/// [PassportBook.closed]: a aba continua no lugar, sem carimbo inventado.
class PassportBook {
  const PassportBook({
    required this.enabled,
    required this.distinctRooms,
    required this.nextRooms,
    required this.nextPoints,
    required this.stamps,
    required this.milestones,
    required this.gifts,
    this.isSample = false,
  });

  final bool enabled;
  final int distinctRooms;
  final int? nextRooms;
  final int? nextPoints;
  final List<PassportStampView> stamps;
  final List<PassportMilestoneView> milestones;
  final List<PassportGiftView> gifts;
  final bool isSample;

  static const closed = PassportBook(
    enabled: false,
    distinctRooms: 0,
    nextRooms: null,
    nextPoints: null,
    stamps: [],
    milestones: [],
    gifts: [],
  );

  static const sample = PassportBook(
    enabled: true,
    distinctRooms: 2,
    nextRooms: 5,
    nextPoints: 500,
    isSample: true,
    stamps: [
      PassportStampView(
        roomId: 'sala-cofre',
        roomName: 'O Cofre',
        venueId: 'casa-ninja',
        venueName: 'Ninja Escape',
        playCount: 2,
      ),
      PassportStampView(
        roomId: 'sala-templo',
        roomName: 'Templo',
        venueId: 'casa-ninja',
        venueName: 'Ninja Escape',
        playCount: 1,
      ),
    ],
    milestones: [
      PassportMilestoneView(key: 'count:5', rooms: 5, points: 500, reached: false),
      PassportMilestoneView(
        key: 'count:10',
        rooms: 10,
        points: 1000,
        reached: false,
      ),
      PassportMilestoneView(
        key: 'count:25',
        rooms: 25,
        points: 3000,
        reached: false,
      ),
    ],
    gifts: [
      PassportGiftView(
        title: 'Foto da sala',
        details: 'Uma foto exclusiva depois do jogo.',
        code: 'FOTO7A2C',
        status: 'available',
        venueName: 'Ninja Escape',
        roomName: 'O Cofre',
      ),
    ],
  );

  factory PassportBook.fromJson(Map<String, dynamic> json) {
    if (json['enabled'] != true) return PassportBook.closed;
    return PassportBook(
      enabled: true,
      distinctRooms: _intOf(json['distinct_rooms']),
      nextRooms: json['next_rooms'] == null ? null : _intOf(json['next_rooms']),
      nextPoints: json['next_points'] == null
          ? null
          : _intOf(json['next_points']),
      stamps: _list(json['stamps']).map(PassportStampView.fromJson).toList(),
      milestones: _list(
        json['milestones'],
      ).map(PassportMilestoneView.fromJson).toList(),
      gifts: _list(json['gifts']).map(PassportGiftView.fromJson).toList(),
    );
  }
}

class PassportStampView {
  const PassportStampView({
    required this.roomId,
    required this.roomName,
    required this.venueId,
    required this.venueName,
    required this.playCount,
  });

  final String roomId;
  final String roomName;
  final String venueId;
  final String venueName;
  final int playCount;

  String get visits => playCount == 1 ? '1 visita' : '$playCount visitas';

  factory PassportStampView.fromJson(Map<String, dynamic> json) {
    return PassportStampView(
      roomId: json['room_id']?.toString() ?? '',
      roomName: json['room_name']?.toString() ?? 'Sala',
      venueId: json['venue_id']?.toString() ?? '',
      venueName: json['venue_name']?.toString() ?? 'Casa',
      playCount: _intOf(json['play_count']),
    );
  }
}

class PassportMilestoneView {
  const PassportMilestoneView({
    required this.key,
    required this.rooms,
    required this.points,
    required this.reached,
    this.venueId,
  });

  final String key;
  final int? rooms;
  final int points;
  final bool reached;
  final String? venueId;

  bool get house => key.startsWith('house:');

  factory PassportMilestoneView.fromJson(Map<String, dynamic> json) {
    return PassportMilestoneView(
      key: json['key']?.toString() ?? '',
      rooms: json['rooms'] == null ? null : _intOf(json['rooms']),
      points: _intOf(json['points']),
      reached: json['reached'] == true,
      venueId: json['venue_id']?.toString(),
    );
  }
}

class PassportGiftView {
  const PassportGiftView({
    required this.title,
    required this.details,
    required this.code,
    required this.status,
    required this.venueName,
    this.roomName,
  });

  final String title;
  final String details;
  final String code;
  final String status;
  final String venueName;
  final String? roomName;

  bool get delivered => status == 'delivered';

  factory PassportGiftView.fromJson(Map<String, dynamic> json) {
    final room = json['room_name']?.toString();
    return PassportGiftView(
      title: json['title']?.toString() ?? 'Mimo',
      details: json['details']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'available',
      venueName: json['venue_name']?.toString() ?? 'Casa',
      roomName: room == null || room.isEmpty ? null : room,
    );
  }
}

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}
