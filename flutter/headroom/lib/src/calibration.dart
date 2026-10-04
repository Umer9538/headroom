import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'basis.dart';
import 'device_info.dart';
import 'interval.dart';
import 'json_support.dart';

/// One device's achieved decode bandwidth and, once probed, its measured
/// ceiling.
final class BandwidthRow {
  /// Creates a row.
  const BandwidthRow({
    required this.soc,
    required this.device,
    required this.decodeTokPerSec,
    required this.tensorBytes,
    required this.achievedGBps,
    required this.ceilingGBps,
    required this.source,
    required this.ceilingSource,
  });

  /// Decodes a row of `calibration.json`.
  factory BandwidthRow.fromJson(Map<String, Object?> json) {
    final ceiling = json['ceilingGBps'];
    return BandwidthRow(
      soc: json['soc'] as String,
      device: json['device'] as String,
      decodeTokPerSec: jsonDouble(json['decodeTokPerSec']),
      tensorBytes: jsonInt(json['tensorBytes']),
      achievedGBps: jsonDouble(json['achievedGBps']),
      ceilingGBps: ceiling == null ? null : jsonDouble(ceiling),
      source: json['source'] as String,
      ceilingSource: json['ceilingSource'] as String?,
    );
  }

  /// The system on a chip, for example `A15 Bionic`.
  final String soc;

  /// The device and OS the decode rate was measured on.
  final String device;

  /// Mean single-stream decode rate over the committed repeats.
  final double decodeTokPerSec;

  /// Weight bytes of the model that was decoded.
  final int tensorBytes;

  /// `decodeTokPerSec × tensorBytes / 1e9`, stored for readability and
  /// checked against the inputs by the test suite.
  final double achievedGBps;

  /// The Headroom triad median on the same device; null until it has been
  /// probed.
  final double? ceilingGBps;

  /// Where the decode rate comes from.
  final String source;

  /// Where the ceiling comes from; null while the ceiling is.
  final String? ceilingSource;

  /// [achievedGBps] recomputed from its inputs.
  double get recomputedAchievedGBps => Calibration.achievedGBps(
    decodeTokPerSec: decodeTokPerSec,
    bytesPerToken: tensorBytes,
  );

  /// η: the share of the measured ceiling that decode actually used; null
  /// until the device has been probed.
  double? get efficiency {
    final ceiling = ceilingGBps;
    return ceiling == null ? null : achievedGBps / ceiling;
  }

  /// The row's JSON form.
  Map<String, Object?> toJson() => {
    'achievedGBps': achievedGBps,
    'ceilingGBps': ceilingGBps,
    'ceilingSource': ceilingSource,
    'decodeTokPerSec': decodeTokPerSec,
    'device': device,
    'soc': soc,
    'source': source,
    'tensorBytes': tensorBytes,
  };
}

/// One device's throughput at the start of a session and after sustained
/// generation.
final class SustainedRow {
  /// Creates a row.
  const SustainedRow({
    required this.soc,
    required this.platform,
    required this.runtime,
    required this.peakTokPerSec,
    required this.sustainedTokPerSec,
    required this.protocolNote,
    required this.source,
  });

  /// Decodes a row of `calibration.json`.
  factory SustainedRow.fromJson(Map<String, Object?> json) => SustainedRow(
    soc: json['soc'] as String,
    platform: HeadroomPlatform.fromJson(json['platform']),
    runtime: json['runtime'] as String,
    peakTokPerSec: jsonDouble(json['peakTokPerSec']),
    sustainedTokPerSec: jsonDouble(json['sustainedTokPerSec']),
    protocolNote: json['protocol'] as String,
    source: json['source'] as String,
  );

  /// The system on a chip.
  final String soc;

  /// The platform the factor applies to.
  final HeadroomPlatform platform;

  /// The inference runtime, for example `llama.cpp-Metal` or `MLX`.
  final String runtime;

  /// Throughput at the start of the session.
  final double peakTokPerSec;

  /// Throughput after sustained generation.
  final double sustainedTokPerSec;

  /// How peak and sustained were measured (the JSON key is `protocol`).
  final String protocolNote;

  /// Where the figures come from.
  final String source;

  /// `sustainedTokPerSec / peakTokPerSec`.
  double get factor => sustainedTokPerSec / peakTokPerSec;

  /// The row's JSON form.
  Map<String, Object?> toJson() => {
    'peakTokPerSec': peakTokPerSec,
    'platform': platform.jsonName,
    'protocol': protocolNote,
    'runtime': runtime,
    'soc': soc,
    'source': source,
    'sustainedTokPerSec': sustainedTokPerSec,
  };
}

/// The committed measurements every calibrated constant is derived from.
///
/// Nothing in here is typed in as a constant: efficiencies and sustained
/// factors are computed from the rows at run time. The shipped rows are a
/// copy of the Swift core's `calibration.json`, kept identical by
/// `tool/sync_native.sh`, and the core's `Calibration/README.md` walks
/// through the arithmetic.
final class Calibration {
  /// Creates a calibration from rows.
  const Calibration({
    this.schemaVersion = 1,
    required this.bandwidth,
    required this.sustained,
  });

  /// Decodes `calibration.json`.
  factory Calibration.fromJson(Map<String, Object?> json) => Calibration(
    schemaVersion: jsonInt(json['schemaVersion']),
    bandwidth: jsonList(
      json['bandwidth'],
      (row) => BandwidthRow.fromJson(jsonMap(row)),
    ),
    sustained: jsonList(
      json['sustained'],
      (row) => SustainedRow.fromJson(jsonMap(row)),
    ),
  );

  /// Decodes `calibration.json` from its text.
  factory Calibration.fromJsonString(String text) =>
      Calibration.fromJson(jsonMap(jsonDecode(text)));

  /// The asset key of the shipped rows.
  static const String assetKey = 'packages/headroom/assets/calibration.json';

  static Calibration? _shipped;

  /// The rows shipped with this package, once [load] has run; null before.
  /// `Headroom.probe()` loads them, so a report it returned can always be
  /// estimated synchronously.
  static Calibration? get shipped => _shipped;

  /// Loads the shipped rows from the package asset, once.
  static Future<Calibration> load() async {
    final loaded = _shipped;
    if (loaded != null) return loaded;
    final text = await rootBundle.loadString(assetKey);
    return _shipped = Calibration.fromJsonString(text);
  }

  /// Schema version of the rows.
  final int schemaVersion;

  /// Achieved decode bandwidth per device, with measured ceilings where
  /// the device has been probed.
  final List<BandwidthRow> bandwidth;

  /// Peak-to-sustained measurements per device.
  final List<SustainedRow> sustained;

  /// Single-stream decode reads every weight once per token, so the decode
  /// rate converts directly into the bandwidth the memory system delivered.
  /// This is PocketRoofline's `achieved_bandwidth`, unchanged.
  static double achievedGBps({
    required double decodeTokPerSec,
    required int bytesPerToken,
  }) => decodeTokPerSec * bytesPerToken / 1e9;

  /// η over every device with a measured ceiling, as the range they span.
  /// The basis says how many devices that is.
  Interval get efficiency {
    final efficiencies = [for (final row in bandwidth) ?row.efficiency];
    if (efficiencies.isEmpty) return Interval.unknown;
    return Interval(
      low: efficiencies.reduce((a, b) => a < b ? a : b),
      high: efficiencies.reduce((a, b) => a > b ? a : b),
      basis: Basis.calibrated(devices: efficiencies.length),
    );
  }

  /// η as it may be applied on [platform].
  ///
  /// Every bandwidth row is an Apple SoC whose ceiling was measured through
  /// Metal, so the range is only meaningful where the probe measures the
  /// same thing. On Android there is no calibration yet, and the answer is
  /// [Interval.unknown] rather than a silently borrowed constant.
  Interval efficiencyFor(HeadroomPlatform platform) =>
      platform.isApple ? efficiency : Interval.unknown;

  /// The peak-to-sustained ratio measured on [platform], or null when no row
  /// describes it. Throttling has only been measured on phones, so this is
  /// null on macOS rather than an assumed 1.0.
  Interval? sustainedFactor(HeadroomPlatform platform) {
    final factors = [
      for (final row in sustained)
        if (row.platform == platform) row.factor,
    ];
    if (factors.isEmpty) return null;
    return Interval(
      low: factors.reduce((a, b) => a < b ? a : b),
      high: factors.reduce((a, b) => a > b ? a : b),
      basis: Basis.calibrated(devices: factors.length),
    );
  }

  /// The JSON form of the rows.
  Map<String, Object?> toJson() => {
    'bandwidth': [for (final row in bandwidth) row.toJson()],
    'schemaVersion': schemaVersion,
    'sustained': [for (final row in sustained) row.toJson()],
  };
}
