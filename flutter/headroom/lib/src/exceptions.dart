/// A probe that could not run or could not be decoded.
///
/// [code] is the platform error code (`invalidOptions`, `probeFailed`,
/// `busy`, `unsupported`, `malformedReport`); [message] says what happened.
/// A probe that cannot measure something (no Metal, allocation failure) is
/// not an exception: the report's `warnings` say so and the section is null.
class HeadroomException implements Exception {
  /// Creates an exception with a stable [code] and a readable [message].
  const HeadroomException(this.code, this.message);

  /// Stable, machine-readable cause.
  final String code;

  /// What happened, for people.
  final String message;

  @override
  String toString() => 'HeadroomException($code): $message';
}

/// The probe was stopped by `Headroom.cancel()` before it finished.
class ProbeCancelledException extends HeadroomException {
  /// Creates the exception.
  const ProbeCancelledException()
    : super('cancelled', 'the probe was cancelled');
}
