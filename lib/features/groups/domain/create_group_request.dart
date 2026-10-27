class CreateGroupRequest {
  const CreateGroupRequest({
    required this.cityId,
    required this.houseId,
    required this.roomId,
    required this.slotId,
    required this.extraSpots,
    required this.creatorUserId,
    required this.creatorDisplayName,
  });

  final String cityId;
  final String houseId;
  final String roomId;
  final String slotId;

  /// Seats the creator is still looking for. The creator is not included.
  final int extraSpots;

  /// Account id of the person creating the group. Comes from the current user.
  final String creatorUserId;

  /// Name shown on the creator's seat. Not hardcoded by the repository.
  final String creatorDisplayName;
}
