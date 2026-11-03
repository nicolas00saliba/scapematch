/// Where a person stands in a group.
///
/// [joined] is the seat they take on entry. [confirmed] means they tapped
/// "Confirmar presença". [cancelled] means they left, were removed, or the
/// organizer cancelled the group. A cancelled seat does not fill a spot.
enum AttendanceStatus { joined, confirmed, cancelled }

/// Pagamento simulado. Entrar deixa a parte pendente até a pessoa pagar.
enum PaymentStatus { pending, paid }

/// What happened to the simulated payment after the person left the seat.
enum RefundStatus { none, refunded, denied }

/// Why [RefundStatus] is what it is. [none] means the seat is still active.
enum RefundReason {
  none,
  cancelledInTime,
  cancelledTooLate,
  organizerCancelledEvent,
  organizerRemovedMember,
  groupDidNotClose,
}

/// The refund a rule function returns. Screens translate it to Portuguese.
class RefundOutcome {
  const RefundOutcome({required this.status, required this.reason});

  final RefundStatus status;
  final RefundReason reason;
}
