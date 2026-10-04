import 'dart:collection';
import 'dart:convert';

/// Reads a JSON number as a double. The Swift core and the Android plugin both
/// write integral doubles without a decimal point (`60`, not `60.0`), so the
/// raw value may arrive as an `int`.
double jsonDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  throw FormatException('expected a number, got ${raw.runtimeType}');
}

/// Reads a JSON number as an integer.
int jsonInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is double && raw == raw.truncateToDouble()) return raw.toInt();
  throw FormatException('expected an integer, got $raw');
}

/// Reads a JSON object.
Map<String, Object?> jsonMap(Object? raw) {
  if (raw is Map) return raw.cast<String, Object?>();
  throw FormatException('expected an object, got ${raw.runtimeType}');
}

/// Reads a JSON array, decoding each element with [decode].
List<T> jsonList<T>(Object? raw, T Function(Object? element) decode) {
  if (raw is List) return List.unmodifiable(raw.map(decode));
  throw FormatException('expected an array, got ${raw.runtimeType}');
}

/// Element-wise equality for the lists the report types hold.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Pretty-prints [value] with two-space indentation and keys in sorted order
/// at every level, the layout the Swift core's `jsonData()` uses, so a report
/// from either platform reads the same way when pasted into a calibration
/// record.
String encodePrettyJson(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(_sortedKeys(value));
}

Object? _sortedKeys(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    value.forEach((key, element) {
      sorted[key as String] = _sortedKeys(element);
    });
    return sorted;
  }
  if (value is List) return value.map(_sortedKeys).toList();
  return value;
}

/// ISO 8601 in UTC at whole-second precision (`2026-10-03T19:50:17Z`), the
/// form Foundation's `.iso8601` date strategy writes.
String formatIso8601Seconds(DateTime time) {
  final utc = time.toUtc();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${pad(utc.month)}-${pad(utc.day)}'
      'T${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)}Z';
}
