import 'json_support.dart';

/// Where a figure comes from.
///
/// Every number Headroom reports carries a basis, so a calibrated estimate can
/// never be read as something measured on this device. The three cases are
/// [MeasuredBasis], [CalibratedBasis] and [UnknownBasis]; switch over them
/// exhaustively, or compare with [Basis.measured] and [Basis.unknown].
sealed class Basis {
  const Basis._();

  /// Measured on this device, during this probe.
  static const Basis measured = MeasuredBasis._();

  /// Not established. Any value alongside it is a stated fallback.
  static const Basis unknown = UnknownBasis._();

  /// Derived from measurements committed for [devices] other devices in
  /// `calibration.json` (the Swift core's `Calibration/README.md` does the
  /// arithmetic), not observed here.
  const factory Basis.calibrated({required int devices}) = CalibratedBasis._;

  /// Decodes the `{"kind": ..., "devices": ...}` object the Swift core writes.
  factory Basis.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'measured' => Basis.measured,
      'calibrated' => Basis.calibrated(devices: jsonInt(json['devices'])),
      'unknown' => Basis.unknown,
      _ => throw FormatException("unrecognised basis '$kind'"),
    };
  }

  /// The basis of a figure derived from this one and [other].
  ///
  /// A derivation is only as well founded as its least-founded input: anything
  /// touched by an unknown is unknown, and anything touched by a calibrated
  /// constant is calibrated on the smaller device count.
  Basis combinedWith(Basis other) {
    return switch ((this, other)) {
      (UnknownBasis(), _) || (_, UnknownBasis()) => Basis.unknown,
      (CalibratedBasis(devices: final a), CalibratedBasis(devices: final b)) =>
        Basis.calibrated(devices: a < b ? a : b),
      (CalibratedBasis(), MeasuredBasis()) => this,
      (MeasuredBasis(), CalibratedBasis()) => other,
      (MeasuredBasis(), MeasuredBasis()) => Basis.measured,
    };
  }

  /// The `{"kind": ...}` object the Swift core reads and writes.
  Map<String, Object?> toJson();
}

/// Measured on this device, during this probe.
final class MeasuredBasis extends Basis {
  const MeasuredBasis._() : super._();

  @override
  Map<String, Object?> toJson() => const {'kind': 'measured'};

  @override
  bool operator ==(Object other) => other is MeasuredBasis;

  @override
  int get hashCode => 'measured'.hashCode;

  @override
  String toString() => 'measured';
}

/// Derived from measurements of [devices] other devices.
final class CalibratedBasis extends Basis {
  const CalibratedBasis._({required this.devices}) : super._();

  /// How many devices with a measured ceiling the constant spans.
  final int devices;

  @override
  Map<String, Object?> toJson() => {'kind': 'calibrated', 'devices': devices};

  @override
  bool operator ==(Object other) =>
      other is CalibratedBasis && other.devices == devices;

  @override
  int get hashCode => Object.hash('calibrated', devices);

  @override
  String toString() => 'calibrated (n=$devices)';
}

/// Not established.
final class UnknownBasis extends Basis {
  const UnknownBasis._() : super._();

  @override
  Map<String, Object?> toJson() => const {'kind': 'unknown'};

  @override
  bool operator ==(Object other) => other is UnknownBasis;

  @override
  int get hashCode => 'unknown'.hashCode;

  @override
  String toString() => 'unknown';
}
