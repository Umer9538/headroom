import 'basis.dart';
import 'interval.dart';
import 'json_support.dart';
import 'quantity.dart';
import 'statistics.dart';

/// The four STREAM kernels, with the byte accounting the benchmark defines:
/// each array an element is read from or written to counts once.
enum StreamKernel {
  /// `c = a`
  copy,

  /// `b = q * c`
  scale,

  /// `c = a + b`
  add,

  /// `a = b + q * c`
  triad;

  /// Decodes the kernel's name.
  static StreamKernel fromJson(Object? raw) => values.firstWhere(
    (kernel) => kernel.name == raw,
    orElse: () => throw FormatException("unrecognised kernel '$raw'"),
  );

  /// Arrays streamed per element: one read and one write for copy and scale,
  /// two reads and one write for add and triad.
  int get arraysTouched => switch (this) {
    copy || scale => 2,
    add || triad => 3,
  };

  /// Bytes one iteration moves over arrays of [arrayBytes] each.
  int bytesPerIteration(int arrayBytes) => arraysTouched * arrayBytes;
}

/// One kernel's bandwidth over its timed iterations.
final class BandwidthFigure {
  const BandwidthFigure._({
    required this.kernel,
    required this.bytesPerIteration,
    required this.iterationSeconds,
    required this.verified,
    required this.bestGBps,
    required this.medianGBps,
    required this.medianCI95GBps,
  });

  /// Summarises timed iterations the way the Swift core does: best and
  /// median rate, and a seeded 95% bootstrap interval of the median, every
  /// figure carrying [basis].
  factory BandwidthFigure.fromIterations({
    required StreamKernel kernel,
    required int bytesPerIteration,
    required List<double> iterationSeconds,
    required bool verified,
    required Basis basis,
  }) {
    if (iterationSeconds.isEmpty) {
      throw ArgumentError('a figure needs at least one timed iteration');
    }
    final rates = [
      for (final seconds in iterationSeconds)
        gigabytesPerSecond(bytes: bytesPerIteration, seconds: seconds),
    ];
    final interval = Statistics.bootstrapMedianInterval(rates);
    return BandwidthFigure._(
      kernel: kernel,
      bytesPerIteration: bytesPerIteration,
      iterationSeconds: List.unmodifiable(iterationSeconds),
      verified: verified,
      bestGBps: Quantity(rates.reduce((a, b) => a > b ? a : b), basis: basis),
      medianGBps: Quantity(Statistics.median(rates), basis: basis),
      medianCI95GBps: Interval(
        low: interval.low,
        high: interval.high,
        basis: basis,
      ),
    );
  }

  /// Decodes a figure as the native side wrote it, keeping its statistics
  /// verbatim rather than recomputing them.
  factory BandwidthFigure.fromJson(Map<String, Object?> json) {
    return BandwidthFigure._(
      kernel: StreamKernel.fromJson(json['kernel']),
      bytesPerIteration: jsonInt(json['bytesPerIteration']),
      iterationSeconds: jsonList(json['iterationSeconds'], jsonDouble),
      verified: json['verified'] as bool,
      bestGBps: Quantity.doubleFromJson(jsonMap(json['bestGBps'])),
      medianGBps: Quantity.doubleFromJson(jsonMap(json['medianGBps'])),
      medianCI95GBps: Interval.fromJson(jsonMap(json['medianCI95GBps'])),
    );
  }

  /// Which STREAM kernel ran.
  final StreamKernel kernel;

  /// Bytes moved per iteration under STREAM accounting.
  final int bytesPerIteration;

  /// Seconds per timed iteration: GPU timestamps for Metal, wall clock for
  /// the CPU.
  final List<double> iterationSeconds;

  /// Whether the kernel's output was read back and matched the expected
  /// arithmetic.
  final bool verified;

  /// The fastest iteration.
  final Quantity<double> bestGBps;

  /// The median iteration; for the GPU triad, the ceiling estimates scale.
  final Quantity<double> medianGBps;

  /// 95% bootstrap confidence interval of the median across iterations.
  final Interval medianCI95GBps;

  /// Decimal gigabytes per second, the unit bandwidth is quoted in
  /// everywhere here.
  static double gigabytesPerSecond({
    required int bytes,
    required double seconds,
  }) => bytes / seconds / 1e9;

  /// Each timed iteration as a rate.
  List<double> get iterationGBps => [
    for (final seconds in iterationSeconds)
      gigabytesPerSecond(bytes: bytesPerIteration, seconds: seconds),
  ];

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    'bestGBps': bestGBps.toJson(),
    'bytesPerIteration': bytesPerIteration,
    'iterationSeconds': iterationSeconds,
    'kernel': kernel.name,
    'medianCI95GBps': medianCI95GBps.toJson(),
    'medianGBps': medianGBps.toJson(),
    'verified': verified,
  };

  @override
  bool operator ==(Object other) =>
      other is BandwidthFigure &&
      other.kernel == kernel &&
      other.bytesPerIteration == bytesPerIteration &&
      listEquals(other.iterationSeconds, iterationSeconds) &&
      other.verified == verified &&
      other.bestGBps == bestGBps &&
      other.medianGBps == medianGBps &&
      other.medianCI95GBps == medianCI95GBps;

  @override
  int get hashCode => Object.hash(
    kernel,
    bytesPerIteration,
    Object.hashAll(iterationSeconds),
    verified,
    bestGBps,
    medianGBps,
    medianCI95GBps,
  );

  @override
  String toString() =>
      '${kernel.name} median ${medianGBps.value.toStringAsFixed(1)} GB/s '
      '(95% CI ${medianCI95GBps.low.toStringAsFixed(1)}–'
      '${medianCI95GBps.high.toStringAsFixed(1)}, '
      'best ${bestGBps.value.toStringAsFixed(1)}) — ${medianGBps.basis}';
}

/// Metal STREAM results. The triad median is the ceiling estimates divide by.
final class GpuBandwidth {
  /// Creates the section from its four figures.
  const GpuBandwidth({
    required this.deviceName,
    required this.arrayBytes,
    required this.copy,
    required this.scale,
    required this.add,
    required this.triad,
  });

  /// Decodes the `gpu` section of a report.
  factory GpuBandwidth.fromJson(Map<String, Object?> json) => GpuBandwidth(
    deviceName: json['deviceName'] as String,
    arrayBytes: jsonInt(json['arrayBytes']),
    copy: BandwidthFigure.fromJson(jsonMap(json['copy'])),
    scale: BandwidthFigure.fromJson(jsonMap(json['scale'])),
    add: BandwidthFigure.fromJson(jsonMap(json['add'])),
    triad: BandwidthFigure.fromJson(jsonMap(json['triad'])),
  );

  /// The Metal device's name, for example `Apple A15 GPU`.
  final String deviceName;

  /// Bytes per array; three are streamed.
  final int arrayBytes;

  /// `c = a`.
  final BandwidthFigure copy;

  /// `b = q * c`.
  final BandwidthFigure scale;

  /// `c = a + b`.
  final BandwidthFigure add;

  /// `a = b + q * c`; its median is the ceiling.
  final BandwidthFigure triad;

  /// The four figures in STREAM order.
  List<BandwidthFigure> get figures => [copy, scale, add, triad];

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    'add': add.toJson(),
    'arrayBytes': arrayBytes,
    'copy': copy.toJson(),
    'deviceName': deviceName,
    'scale': scale.toJson(),
    'triad': triad.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is GpuBandwidth &&
      other.deviceName == deviceName &&
      other.arrayBytes == arrayBytes &&
      other.copy == copy &&
      other.scale == scale &&
      other.add == add &&
      other.triad == triad;

  @override
  int get hashCode =>
      Object.hash(deviceName, arrayBytes, copy, scale, add, triad);
}

/// One thread count's run of the CPU triad.
final class CpuAttempt {
  /// Creates an attempt.
  const CpuAttempt({required this.threads, required this.triad});

  /// Decodes one entry of `cpu.attempts`.
  factory CpuAttempt.fromJson(Map<String, Object?> json) => CpuAttempt(
    threads: jsonInt(json['threads']),
    triad: BandwidthFigure.fromJson(jsonMap(json['triad'])),
  );

  /// Threads the triad ran on.
  final int threads;

  /// The figure that run produced.
  final BandwidthFigure triad;

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {'threads': threads, 'triad': triad.toJson()};

  @override
  bool operator ==(Object other) =>
      other is CpuAttempt && other.threads == threads && other.triad == triad;

  @override
  int get hashCode => Object.hash(threads, triad);
}

/// STREAM triad on the CPU. A ceiling for CPU inference backends only;
/// estimates do not use it.
///
/// The probe may try more than one thread count (on Apple silicon the
/// performance cluster alone, then every core) and reports the attempt with
/// the highest verified median; [attempts] keeps every run so the choice can
/// be audited.
final class CpuBandwidth {
  /// Creates the section from its figure and the attempts behind it.
  const CpuBandwidth({
    required this.threads,
    required this.arrayBytes,
    required this.compiledWithOptimisation,
    required this.triad,
    required this.attempts,
  });

  /// Decodes the `cpu` section of a report. Records written before thread
  /// counts were tried in turn carry no `attempts`; their one run is then
  /// their only attempt.
  factory CpuBandwidth.fromJson(Map<String, Object?> json) {
    final threads = jsonInt(json['threads']);
    final triad = BandwidthFigure.fromJson(jsonMap(json['triad']));
    final attempts = json['attempts'];
    return CpuBandwidth(
      threads: threads,
      arrayBytes: jsonInt(json['arrayBytes']),
      compiledWithOptimisation: json['compiledWithOptimisation'] as bool,
      triad: triad,
      attempts: attempts == null
          ? [CpuAttempt(threads: threads, triad: triad)]
          : jsonList(
              attempts,
              (attempt) => CpuAttempt.fromJson(jsonMap(attempt)),
            ),
    );
  }

  /// The thread count behind [triad]: the attempt with the highest median.
  final int threads;

  /// Bytes per array; three are streamed.
  final int arrayBytes;

  /// False when the C core was compiled without optimisation, in which case
  /// the vector loop spills to the stack and the figure carries basis
  /// unknown.
  final bool compiledWithOptimisation;

  /// `a = b + q * c`, from the best attempt.
  final BandwidthFigure triad;

  /// Every thread count tried, [threads] included.
  final List<CpuAttempt> attempts;

  /// The verified attempt with the highest median, or the highest
  /// unverified one when none verified (its basis is already unknown). The
  /// same rule as the Swift core's `CPUBandwidth.best(of:)`.
  static CpuAttempt bestOf(List<CpuAttempt> attempts) {
    if (attempts.isEmpty) {
      throw ArgumentError('at least one thread count must have run');
    }
    final verified = [
      for (final attempt in attempts)
        if (attempt.triad.verified) attempt,
    ];
    return (verified.isEmpty ? attempts : verified).reduce(
      (a, b) => b.triad.medianGBps.value > a.triad.medianGBps.value ? b : a,
    );
  }

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    'arrayBytes': arrayBytes,
    'attempts': [for (final attempt in attempts) attempt.toJson()],
    'compiledWithOptimisation': compiledWithOptimisation,
    'threads': threads,
    'triad': triad.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CpuBandwidth &&
      other.threads == threads &&
      other.arrayBytes == arrayBytes &&
      other.compiledWithOptimisation == compiledWithOptimisation &&
      other.triad == triad &&
      listEquals(other.attempts, attempts);

  @override
  int get hashCode => Object.hash(
    threads,
    arrayBytes,
    compiledWithOptimisation,
    triad,
    Object.hashAll(attempts),
  );
}
