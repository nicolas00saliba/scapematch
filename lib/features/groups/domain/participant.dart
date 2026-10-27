import 'package:scapematch/features/groups/domain/attendance.dart';

class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    required this.isCreator,
    required this.isLocalUser,
    this.userId,
    this.attendance = AttendanceStatus.joined,
    this.payment = PaymentStatus.paid,
    this.refund = RefundStatus.none,
    this.refundReason = RefundReason.none,
  });

  /// Membership id. Unique inside the database, not the account id.
  final String id;

  /// Account id when this seat belongs to a known user.
  /// Sample players leave this null. The local stand-in user fills it
  /// from the current-user provider so login can match the same field later.
  final String? userId;

  final String displayName;
  final bool isCreator;

  /// True when this seat is the person using this app session.
  /// A shared database should compare [userId] instead of trusting this flag.
  final bool isLocalUser;

  final AttendanceStatus attendance;
  final PaymentStatus payment;
  final RefundStatus refund;
  final RefundReason refundReason;

  /// False after the person leaves, is removed, or the group is cancelled.
  bool get occupiesSeat => attendance != AttendanceStatus.cancelled;

  bool get isConfirmed => attendance == AttendanceStatus.confirmed;

  Participant copyWith({
    AttendanceStatus? attendance,
    PaymentStatus? payment,
    RefundStatus? refund,
    RefundReason? refundReason,
  }) {
    return Participant(
      id: id,
      userId: userId,
      displayName: displayName,
      isCreator: isCreator,
      isLocalUser: isLocalUser,
      attendance: attendance ?? this.attendance,
      payment: payment ?? this.payment,
      refund: refund ?? this.refund,
      refundReason: refundReason ?? this.refundReason,
    );
  }
}
