/// The app's idea of "now".
///
/// Rules and repositories take this instead of calling [DateTime.now], so a
/// test can freeze the clock. The only [DateTime.now] in the app is
/// [SystemClock].
abstract class Clock {
  const Clock();

  DateTime now();
}

/// Wall clock used by the running app.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Clock that always returns [instant]. Tests move [instant] when they need
/// a later moment without sleeping.
class FixedClock extends Clock {
  FixedClock(this.instant);

  DateTime instant;

  @override
  DateTime now() => instant;
}
