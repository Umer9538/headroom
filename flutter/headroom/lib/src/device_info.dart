import 'json_support.dart';

/// The platform a report was captured on.
///
/// The first three values are the Swift core's; the Android values are this
/// plugin's addition to the report schema. Simulator and emulator figures
/// are the host machine's and must never pass for phone data.
enum HeadroomPlatform {
  /// A physical iPhone or iPad.
  iOS('iOS'),

  /// The iOS Simulator; figures are the host Mac's.
  iOSSimulator('iOS Simulator'),

  /// A Mac.
  macOS('macOS'),

  /// A physical Android device.
  android('Android'),

  /// The Android Emulator; figures are the host machine's.
  androidEmulator('Android Emulator');

  const HeadroomPlatform(this.jsonName);

  /// The string the report stores.
  final String jsonName;

  /// Decodes the stored string.
  static HeadroomPlatform fromJson(Object? raw) => values.firstWhere(
    (platform) => platform.jsonName == raw,
    orElse: () => throw FormatException("unrecognised platform '$raw'"),
  );

  /// True for the iOS Simulator and the Android Emulator.
  bool get isSimulator => this == iOSSimulator || this == androidEmulator;

  /// True for iOS, the iOS Simulator and macOS: the platforms whose
  /// ceilings are measured through Metal, which is what the shipped
  /// calibration describes.
  bool get isApple => this == iOS || this == iOSSimulator || this == macOS;
}

/// Hardware and OS facts that do not change during a probe.
final class DeviceInfo {
  /// Creates the section.
  const DeviceInfo({
    required this.identifier,
    required this.chip,
    required this.platform,
    required this.osVersion,
    required this.osBuild,
    required this.logicalCPUs,
  });

  /// Decodes the `device` section of a report.
  factory DeviceInfo.fromJson(Map<String, Object?> json) => DeviceInfo(
    identifier: json['identifier'] as String,
    chip: json['chip'] as String?,
    platform: HeadroomPlatform.fromJson(json['platform']),
    osVersion: json['osVersion'] as String,
    osBuild: json['osBuild'] as String,
    logicalCPUs: jsonInt(json['logicalCPUs']),
  );

  /// `iPhone14,5` on iOS (uname), `MacBookPro17,1` on macOS (`hw.model`),
  /// and `Build.MANUFACTURER Build.MODEL` on Android.
  final String identifier;

  /// `Apple M1` where the kernel exposes a brand string (macOS); on Android
  /// `Build.SOC_MANUFACTURER Build.SOC_MODEL` from API 31, `unknown` below
  /// it; null on iOS.
  final String? chip;

  /// Which platform, and whether it is a simulator.
  final HeadroomPlatform platform;

  /// `26.6.1` on Apple platforms; `Build.VERSION.RELEASE` on Android.
  final String osVersion;

  /// `23G83` on Apple platforms; `Build.ID` on Android.
  final String osBuild;

  /// Online logical CPUs.
  final int logicalCPUs;

  /// Simulator figures are the host machine's and must never pass for
  /// phone data.
  bool get isSimulator => platform.isSimulator;

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    if (chip != null) 'chip': chip,
    'identifier': identifier,
    'logicalCPUs': logicalCPUs,
    'osBuild': osBuild,
    'osVersion': osVersion,
    'platform': platform.jsonName,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceInfo &&
      other.identifier == identifier &&
      other.chip == chip &&
      other.platform == platform &&
      other.osVersion == osVersion &&
      other.osBuild == osBuild &&
      other.logicalCPUs == logicalCPUs;

  @override
  int get hashCode =>
      Object.hash(identifier, chip, platform, osVersion, osBuild, logicalCPUs);
}
