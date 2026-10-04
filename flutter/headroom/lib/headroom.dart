/// A two-second, on-device probe of memory bandwidth, and what it means for
/// an LLM of a given size: decode speed as an interval, sustained speed after
/// throttling, and whether the model fits, with a basis on every figure.
///
/// Start with [Headroom.probe], then [ProbeReport.estimate].
library;

export 'src/bandwidth_figure.dart';
export 'src/basis.dart';
export 'src/calibration.dart';
export 'src/conditions.dart';
export 'src/device_info.dart';
export 'src/estimate.dart';
export 'src/exceptions.dart';
export 'src/headroom.dart';
export 'src/interval.dart';
export 'src/memory_fit.dart';
export 'src/memory_info.dart';
export 'src/model_spec.dart';
export 'src/probe_options.dart';
export 'src/probe_report.dart';
export 'src/quantity.dart';
export 'src/statistics.dart';
