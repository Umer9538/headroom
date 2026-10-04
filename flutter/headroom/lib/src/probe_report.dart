import 'dart:convert';

import 'bandwidth_figure.dart';
import 'basis.dart';
import 'calibration.dart';
import 'conditions.dart';
import 'device_info.dart';
import 'estimate.dart';
import 'interval.dart';
import 'json_support.dart';
import 'memory_fit.dart';
import 'memory_info.dart';
import 'model_spec.dart';
import 'quantity.dart';

/// Everything one probe observed, serialisable so a device's result can be
/// pasted back into `calibration.json`.
///
/// The JSON form is the Swift core's schema version 1, with two additions
/// this plugin makes for Android: the `Android` and `Android Emulator`
/// platform values, and the optional `memory.lowMemory`,
/// `memory.lowMemoryThresholdBytes` and `conditions.platformThermalStatus`
/// fields.
final class ProbeReport {
  /// Creates a report from its sections. [capturedAt] is truncated to whole
  /// seconds, as the Swift core does, because ISO 8601 carries whole seconds
  /// and a report decoded from its own JSON must compare equal.
  ProbeReport({
    required this.schemaVersion,
    required this.headroomVersion,
    required DateTime capturedAt,
    required this.durationSeconds,
    required this.device,
    required this.conditions,
    required this.memory,
    required this.gpu,
    required this.cpu,
    required this.warnings,
  }) : capturedAt = DateTime.fromMillisecondsSinceEpoch(
         capturedAt.millisecondsSinceEpoch -
             capturedAt.millisecondsSinceEpoch % 1000,
         isUtc: true,
       );

  /// Decodes a report object.
  factory ProbeReport.fromJson(Map<String, Object?> json) {
    final gpu = json['gpu'];
    final cpu = json['cpu'];
    return ProbeReport(
      schemaVersion: jsonInt(json['schemaVersion']),
      headroomVersion: json['headroomVersion'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String).toUtc(),
      durationSeconds: jsonDouble(json['durationSeconds']),
      device: DeviceInfo.fromJson(jsonMap(json['device'])),
      conditions: Conditions.fromJson(jsonMap(json['conditions'])),
      memory: MemoryInfo.fromJson(jsonMap(json['memory'])),
      gpu: gpu == null ? null : GpuBandwidth.fromJson(jsonMap(gpu)),
      cpu: cpu == null ? null : CpuBandwidth.fromJson(jsonMap(cpu)),
      warnings: jsonList(json['warnings'], (warning) => warning as String),
    );
  }

  /// Decodes a report from its JSON text, as the native side returns it.
  factory ProbeReport.fromJsonString(String text) =>
      ProbeReport.fromJson(jsonMap(jsonDecode(text)));

  /// Schema version of the report; 1 today.
  final int schemaVersion;

  /// Version of the probe core that produced the report.
  final String headroomVersion;

  /// When the probe started, in UTC.
  final DateTime capturedAt;

  /// How long the probe took.
  final double durationSeconds;

  /// Hardware and OS.
  final DeviceInfo device;

  /// Thermal state, power and battery.
  final Conditions conditions;

  /// Installed and available memory.
  final MemoryInfo memory;

  /// Null when Metal was unavailable, a buffer could not be allocated, or
  /// the platform has no GPU probe; [warnings] says which.
  final GpuBandwidth? gpu;

  /// Null when the CPU probe did not run; [warnings] says why.
  final CpuBandwidth? cpu;

  /// Everything that did not go to plan, in plain words.
  final List<String> warnings;

  /// The memory-bandwidth ceiling estimates scale: the Metal triad median.
  Quantity<double>? get ceilingGBps => gpu?.triad.medianGBps;

  /// Predicts decode throughput and memory fit for [model] with
  /// [contextTokens] already in the KV cache.
  ///
  /// `peak = ceiling × η / bytesPerToken`, as an interval spanning the
  /// ceiling's confidence interval and the calibrated efficiency range;
  /// `sustained = peak × sustainedFactor`. On Android no calibration exists
  /// yet, so η and the prediction are unknown and the notes say so.
  ///
  /// [calibration] defaults to the shipped rows, which `Headroom.probe()`
  /// loads; a report decoded from JSON without a prior probe needs
  /// `await Calibration.load()` first, or an explicit calibration.
  Estimate estimate(
    ModelSpec model, {
    required int contextTokens,
    Calibration? calibration,
  }) {
    if (contextTokens < 0) throw ArgumentError('context cannot be negative');
    final rows =
        calibration ??
        Calibration.shipped ??
        (throw StateError(
          'the shipped calibration is not loaded: call Headroom.probe() or '
          'await Calibration.load() first, or pass a calibration',
        ));
    final notes = <String>[];
    final bytesPerToken = model.bytesPerToken(contextTokens: contextTokens);
    final efficiency = rows.efficiencyFor(device.platform);
    if (!device.platform.isApple) {
      notes.add(
        'Prediction is unknown: no Android calibration yet. The efficiency η '
        'comes from Apple SoCs measured against a Metal ceiling and is not '
        'applied here.',
      );
    } else if (!efficiency.isKnown) {
      notes.add(
        'No calibration device has a measured ceiling, so efficiency is '
        'unknown.',
      );
    }

    final ceiling = gpu?.triad.medianCI95GBps;
    final Interval peak;
    if (ceiling != null) {
      // GB/s × η → GB/s of weights; × 1e9 / bytes per token → tokens per second.
      peak = ceiling
          .multipliedBy(efficiency)
          .scaledBy(1e9)
          .dividedBy(bytesPerToken.toDouble());
    } else {
      peak = Interval.unknown;
      notes.add('The GPU probe did not run, so throughput is unknown.');
    }

    final sustainedFactor = rows.sustainedFactor(device.platform);
    if (sustainedFactor != null) {
      final applicable = [
        for (final row in rows.sustained)
          if (row.platform == device.platform) row,
      ];
      final runtimes = ({for (final row in applicable) row.runtime}.toList()
            ..sort())
          .join(', ');
      notes.add(
        'Sustained factor comes from ${applicable.length} phone(s) on '
        '$runtimes; it is a throttling range, not this device\'s.',
      );
    } else {
      notes.add(
        'No sustained factor applies: throttling has only been calibrated on '
        'iPhones.',
      );
    }

    if (model.kv == null) {
      notes.add(
        '${model.name} has no layer geometry, so the KV cache is not '
        'modelled: bytes per token are weights only.',
      );
    }
    if (memory.availableBytes.basis != Basis.measured) {
      notes.add(
        'Available memory is a fallback: this platform exposes no per-process '
        'budget, so the fit verdict is unknown.',
      );
    }

    return Estimate(
      model: model,
      contextTokens: contextTokens,
      bytesPerToken: bytesPerToken,
      ceilingGBps: ceiling,
      efficiency: efficiency,
      peak: peak,
      sustainedFactor: sustainedFactor,
      sustained: sustainedFactor == null
          ? null
          : peak.multipliedBy(sustainedFactor),
      fit: MemoryFit.compute(
        model: model,
        contextTokens: contextTokens,
        available: memory.availableBytes,
      ),
      notes: List.unmodifiable(notes),
    );
  }

  /// The object form the Swift core reads and writes; null sections are
  /// omitted.
  Map<String, Object?> toJson() => {
    'capturedAt': formatIso8601Seconds(capturedAt),
    'conditions': conditions.toJson(),
    if (cpu != null) 'cpu': cpu!.toJson(),
    'device': device.toJson(),
    'durationSeconds': durationSeconds,
    if (gpu != null) 'gpu': gpu!.toJson(),
    'headroomVersion': headroomVersion,
    'memory': memory.toJson(),
    'schemaVersion': schemaVersion,
    'warnings': warnings,
  };

  /// Pretty-printed JSON with sorted keys, the layout the Swift core's
  /// `jsonData()` produces, for pasting into a calibration record.
  String toJsonString() => encodePrettyJson(toJson());

  @override
  bool operator ==(Object other) =>
      other is ProbeReport &&
      other.schemaVersion == schemaVersion &&
      other.headroomVersion == headroomVersion &&
      other.capturedAt == capturedAt &&
      other.durationSeconds == durationSeconds &&
      other.device == device &&
      other.conditions == conditions &&
      other.memory == memory &&
      other.gpu == gpu &&
      other.cpu == cpu &&
      listEquals(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    headroomVersion,
    capturedAt,
    durationSeconds,
    device,
    conditions,
    memory,
    gpu,
    cpu,
    Object.hashAll(warnings),
  );
}
