import 'package:flutter/services.dart';

import 'calibration.dart';
import 'exceptions.dart';
import 'probe_options.dart';
import 'probe_report.dart';

/// The probe.
///
/// ```dart
/// final report = await Headroom.probe();          // one to two seconds
/// report.ceilingGBps;                              // Quantity(57.4, basis: measured) on iOS
/// final estimate = report.estimate(ModelSpec.tinyLlama1_1BQ4_0, contextTokens: 1024);
/// estimate.peak;                                   // Interval, basis calibrated (n=1) on iOS, unknown on Android
/// ```
abstract final class Headroom {
  /// This plugin's version.
  static const String version = '0.1.0';

  /// The channel the native probes answer on. `probe` takes
  /// [ProbeOptions.toChannelArguments] and returns the report as a JSON
  /// string; `cancel` stops a running probe at its next stage boundary.
  static const MethodChannel channel = MethodChannel('headroom/probe');

  static Future<ProbeReport>? _inFlight;
  static bool _cancelRequested = false;

  /// Whether a probe is running.
  static bool get isProbing => _inFlight != null;

  /// Measures this device's memory-bandwidth ceilings and records the
  /// conditions they were measured under.
  ///
  /// Takes one to two seconds; the native work runs off the platform thread,
  /// so the UI stays responsive. One probe runs at a time: a second call
  /// while one is in flight throws a [HeadroomException] with code `busy`.
  /// [cancel] stops it at the next stage boundary, after which this future
  /// completes with a [ProbeCancelledException].
  ///
  /// A probe that cannot measure something (no Metal, allocation failure,
  /// no GPU probe on Android) is reported in [ProbeReport.warnings] with its
  /// section null rather than thrown, so the rest of the report is usable.
  static Future<ProbeReport> probe({
    ProbeOptions options = const ProbeOptions(),
  }) async {
    options.validate();
    if (_inFlight != null) {
      throw const HeadroomException(
        'busy',
        'a probe is already running; await it or call Headroom.cancel() first',
      );
    }
    _cancelRequested = false;
    final run = _run(options);
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  /// Stops the running probe, if any, at its next stage boundary; a probe
  /// that has not reached the native side yet never starts. The pending
  /// [probe] future then completes with a [ProbeCancelledException].
  static Future<void> cancel() async {
    if (_inFlight == null) return;
    _cancelRequested = true;
    try {
      await channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Nothing is running natively on a platform without the plugin.
    }
  }

  static Future<ProbeReport> _run(ProbeOptions options) async {
    // Loaded first so the returned report can be estimated synchronously.
    await Calibration.load();
    if (_cancelRequested) throw const ProbeCancelledException();
    final String? json;
    try {
      json = await channel.invokeMethod<String>(
        'probe',
        options.toChannelArguments(),
      );
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') throw const ProbeCancelledException();
      throw HeadroomException(error.code, error.message ?? error.code);
    } on MissingPluginException {
      throw const HeadroomException(
        'unsupported',
        'Headroom probes iOS and Android only',
      );
    }
    if (json == null) {
      throw const HeadroomException(
        'malformedReport',
        'the native probe returned no report',
      );
    }
    try {
      return ProbeReport.fromJsonString(json);
    } on FormatException catch (error) {
      throw HeadroomException('malformedReport', error.message);
    } on TypeError catch (error) {
      throw HeadroomException('malformedReport', error.toString());
    }
  }
}
