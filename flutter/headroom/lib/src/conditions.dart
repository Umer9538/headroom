import 'json_support.dart';

/// The operating system's thermal pressure level when the probe ran.
///
/// On Apple platforms this is `ProcessInfo.thermalState`. On Android it is
/// `PowerManager.currentThermalStatus`, folded as NONE → [nominal],
/// LIGHT and MODERATE → [fair], SEVERE → [serious], and CRITICAL, EMERGENCY
/// and SHUTDOWN → [critical]; the raw status is kept in
/// [Conditions.platformThermalStatus].
enum ThermalState {
  /// No thermal pressure.
  nominal,

  /// Some throttling may be in effect.
  fair,

  /// Performance is being reduced.
  serious,

  /// The device is close to its limits.
  critical,

  /// A state this build does not know; newer OS releases may add one.
  unrecognised;

  /// Decodes the state's name.
  static ThermalState fromJson(Object? raw) => values.firstWhere(
    (state) => state.name == raw,
    orElse: () => throw FormatException("unrecognised thermal state '$raw'"),
  );
}

/// What was powering the device.
enum PowerSource {
  /// Running on the battery.
  battery,

  /// Plugged in: mains, USB or wireless.
  external,

  /// The OS did not say.
  unknown;

  /// Decodes the source's name.
  static PowerSource fromJson(Object? raw) => values.firstWhere(
    (source) => source.name == raw,
    orElse: () => throw FormatException("unrecognised power source '$raw'"),
  );
}

/// What the device was doing when the probe ran: the context without which a
/// bandwidth figure cannot be compared with another.
final class Conditions {
  /// Creates the section.
  const Conditions({
    required this.thermalState,
    required this.isLowPowerModeEnabled,
    required this.powerSource,
    this.batteryLevel,
    this.platformThermalStatus,
  });

  /// Decodes the `conditions` section of a report.
  factory Conditions.fromJson(Map<String, Object?> json) {
    final level = json['batteryLevel'];
    return Conditions(
      thermalState: ThermalState.fromJson(json['thermalState']),
      isLowPowerModeEnabled: json['isLowPowerModeEnabled'] as bool,
      powerSource: PowerSource.fromJson(json['powerSource']),
      batteryLevel: level == null ? null : jsonDouble(level),
      platformThermalStatus: json['platformThermalStatus'] as String?,
    );
  }

  /// The folded thermal level.
  final ThermalState thermalState;

  /// Low Power Mode on iOS, Battery Saver on Android.
  final bool isLowPowerModeEnabled;

  /// Battery or external power.
  final PowerSource powerSource;

  /// `0...1` where the OS reports it (phones); null elsewhere.
  final double? batteryLevel;

  /// The OS's own thermal status name before folding, where it has more
  /// levels than [ThermalState]: Android's `NONE`, `LIGHT`, `MODERATE`,
  /// `SEVERE`, `CRITICAL`, `EMERGENCY` or `SHUTDOWN`. Null on Apple
  /// platforms, whose levels map one to one.
  final String? platformThermalStatus;

  /// The object form the Swift core reads and writes; optional fields are
  /// omitted when null, as Swift's `Codable` does.
  Map<String, Object?> toJson() => {
    if (batteryLevel != null) 'batteryLevel': batteryLevel,
    'isLowPowerModeEnabled': isLowPowerModeEnabled,
    if (platformThermalStatus != null)
      'platformThermalStatus': platformThermalStatus,
    'powerSource': powerSource.name,
    'thermalState': thermalState.name,
  };

  @override
  bool operator ==(Object other) =>
      other is Conditions &&
      other.thermalState == thermalState &&
      other.isLowPowerModeEnabled == isLowPowerModeEnabled &&
      other.powerSource == powerSource &&
      other.batteryLevel == batteryLevel &&
      other.platformThermalStatus == platformThermalStatus;

  @override
  int get hashCode => Object.hash(
    thermalState,
    isLowPowerModeEnabled,
    powerSource,
    batteryLevel,
    platformThermalStatus,
  );
}
