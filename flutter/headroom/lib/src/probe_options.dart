/// Probe sizing. The defaults take one to two seconds and stream arrays far
/// larger than any last-level cache in the devices Headroom has run on.
final class ProbeOptions {
  /// Creates options; see each field for the defaults.
  const ProbeOptions({
    this.gpuArrayBytes = 128 << 20,
    this.gpuWarmupIterations = 1,
    this.gpuTimedIterations = 10,
    this.cpuArrayBytes = 64 << 20,
    this.cpuThreads = 0,
    this.cpuWarmupIterations = 1,
    this.cpuTimedIterations = 7,
    this.runsGPUProbe = true,
    this.runsCPUProbe = true,
  });

  /// Threads per Metal threadgroup; GPU arrays are sized in whole groups.
  static const int gpuThreadgroupWidth = 256;

  /// Bytes per GPU thread: one `float4`.
  static const int gpuVectorBytes = 16;

  /// Per array; three are allocated in private GPU memory. Must be a positive
  /// multiple of [gpuThreadgroupWidth] × [gpuVectorBytes].
  final int gpuArrayBytes;

  /// Untimed dispatches per kernel before timing starts.
  final int gpuWarmupIterations;

  /// Timed dispatches per kernel.
  final int gpuTimedIterations;

  /// Per array; three are allocated in system memory.
  final int cpuArrayBytes;

  /// 0 means one thread per online logical CPU.
  final int cpuThreads;

  /// Untimed iterations before timing starts.
  final int cpuWarmupIterations;

  /// Timed iterations.
  final int cpuTimedIterations;

  /// Whether to run the Metal STREAM probe. Android has no GPU probe in this
  /// version; the report says so when this is true.
  final bool runsGPUProbe;

  /// Whether to run the CPU triad.
  final bool runsCPUProbe;

  /// Throws [ArgumentError] for sizes the probes cannot run, with the same
  /// rules as the Swift core's `ProbeOptions.validate()`.
  void validate() {
    final gpuGranule = gpuThreadgroupWidth * gpuVectorBytes;
    if (gpuArrayBytes <= 0 || gpuArrayBytes % gpuGranule != 0) {
      throw ArgumentError('gpuArrayBytes must be a positive multiple of $gpuGranule');
    }
    if (cpuArrayBytes < 4 || cpuArrayBytes % 4 != 0) {
      throw ArgumentError('cpuArrayBytes must be a positive multiple of 4');
    }
    if (gpuTimedIterations < 1 || cpuTimedIterations < 1) {
      throw ArgumentError('each probe needs at least one timed iteration');
    }
    if (gpuWarmupIterations < 0 || cpuWarmupIterations < 0 || cpuThreads < 0) {
      throw ArgumentError(
        'warm-up iterations and thread count cannot be negative',
      );
    }
  }

  /// A copy with some fields replaced.
  ProbeOptions copyWith({
    int? gpuArrayBytes,
    int? gpuWarmupIterations,
    int? gpuTimedIterations,
    int? cpuArrayBytes,
    int? cpuThreads,
    int? cpuWarmupIterations,
    int? cpuTimedIterations,
    bool? runsGPUProbe,
    bool? runsCPUProbe,
  }) => ProbeOptions(
    gpuArrayBytes: gpuArrayBytes ?? this.gpuArrayBytes,
    gpuWarmupIterations: gpuWarmupIterations ?? this.gpuWarmupIterations,
    gpuTimedIterations: gpuTimedIterations ?? this.gpuTimedIterations,
    cpuArrayBytes: cpuArrayBytes ?? this.cpuArrayBytes,
    cpuThreads: cpuThreads ?? this.cpuThreads,
    cpuWarmupIterations: cpuWarmupIterations ?? this.cpuWarmupIterations,
    cpuTimedIterations: cpuTimedIterations ?? this.cpuTimedIterations,
    runsGPUProbe: runsGPUProbe ?? this.runsGPUProbe,
    runsCPUProbe: runsCPUProbe ?? this.runsCPUProbe,
  );

  /// The arguments the `headroom/probe` channel's `probe` method takes.
  Map<String, Object?> toChannelArguments() => {
    'gpuArrayBytes': gpuArrayBytes,
    'gpuWarmupIterations': gpuWarmupIterations,
    'gpuTimedIterations': gpuTimedIterations,
    'cpuArrayBytes': cpuArrayBytes,
    'cpuThreads': cpuThreads,
    'cpuWarmupIterations': cpuWarmupIterations,
    'cpuTimedIterations': cpuTimedIterations,
    'runsGPUProbe': runsGPUProbe,
    'runsCPUProbe': runsCPUProbe,
  };

  @override
  bool operator ==(Object other) =>
      other is ProbeOptions &&
      other.gpuArrayBytes == gpuArrayBytes &&
      other.gpuWarmupIterations == gpuWarmupIterations &&
      other.gpuTimedIterations == gpuTimedIterations &&
      other.cpuArrayBytes == cpuArrayBytes &&
      other.cpuThreads == cpuThreads &&
      other.cpuWarmupIterations == cpuWarmupIterations &&
      other.cpuTimedIterations == cpuTimedIterations &&
      other.runsGPUProbe == runsGPUProbe &&
      other.runsCPUProbe == runsCPUProbe;

  @override
  int get hashCode => Object.hash(
    gpuArrayBytes,
    gpuWarmupIterations,
    gpuTimedIterations,
    cpuArrayBytes,
    cpuThreads,
    cpuWarmupIterations,
    cpuTimedIterations,
    runsGPUProbe,
    runsCPUProbe,
  );
}
