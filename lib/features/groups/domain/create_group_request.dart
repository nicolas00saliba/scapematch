class CreateGroupRequest {
  const CreateGroupRequest({
    required this.cityId,
    required this.houseId,
    required this.roomId,
    required this.slotId,
    required this.extraSpots,
  });

  final String cityId;
  final String houseId;
  final String roomId;
  final String slotId;

  /// Seats the creator is still looking for. The creator is not included.
  final int extraSpots;
}
