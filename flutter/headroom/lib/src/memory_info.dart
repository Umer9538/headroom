import 'json_support.dart';
import 'quantity.dart';

/// Installed and remaining memory. "Remaining" decides whether a model fits.
///
/// On iOS it is `os_proc_available_memory`, the budget this process may still
/// allocate before jetsam, basis measured. On Android it is
/// `ActivityManager.MemoryInfo.availMem`, what the system considers
/// available before it starts killing background processes, basis measured;
/// [lowMemory] and [lowMemoryThresholdBytes] come from the same call. On
/// macOS no per-process budget exists and the figure is a fallback with
/// basis unknown.
final class MemoryInfo {
  /// Creates the section.
  const MemoryInfo({
    required this.physicalBytes,
    required this.availableBytes,
    this.lowMemory,
    this.lowMemoryThresholdBytes,
  });

  /// Decodes the `memory` section of a report.
  factory MemoryInfo.fromJson(Map<String, Object?> json) {
    final threshold = json['lowMemoryThresholdBytes'];
    return MemoryInfo(
      physicalBytes: jsonInt(json['physicalBytes']),
      availableBytes: Quantity.intFromJson(jsonMap(json['availableBytes'])),
      lowMemory: json['lowMemory'] as bool?,
      lowMemoryThresholdBytes: threshold == null ? null : jsonInt(threshold),
    );
  }

  /// Installed RAM in bytes.
  final int physicalBytes;

  /// What the process may still use, with the basis of that figure.
  final Quantity<int> availableBytes;

  /// Android's `MemoryInfo.lowMemory`: the system is already short of
  /// memory. Null on Apple platforms.
  final bool? lowMemory;

  /// Android's `MemoryInfo.threshold`: the available-memory level below
  /// which the system starts killing background processes. Null on Apple
  /// platforms.
  final int? lowMemoryThresholdBytes;

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {
    'availableBytes': availableBytes.toJson(),
    if (lowMemory != null) 'lowMemory': lowMemory,
    if (lowMemoryThresholdBytes != null)
      'lowMemoryThresholdBytes': lowMemoryThresholdBytes,
    'physicalBytes': physicalBytes,
  };

  @override
  bool operator ==(Object other) =>
      other is MemoryInfo &&
      other.physicalBytes == physicalBytes &&
      other.availableBytes == availableBytes &&
      other.lowMemory == lowMemory &&
      other.lowMemoryThresholdBytes == lowMemoryThresholdBytes;

  @override
  int get hashCode => Object.hash(
    physicalBytes,
    availableBytes,
    lowMemory,
    lowMemoryThresholdBytes,
  );
}
