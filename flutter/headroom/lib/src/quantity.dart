import 'basis.dart';
import 'json_support.dart';

/// A value and the basis on which it is reported.
final class Quantity<T extends Object> {
  /// Pairs [value] with the [basis] it rests on.
  const Quantity(this.value, {required this.basis});

  /// The figure.
  final T value;

  /// Where the figure comes from.
  final Basis basis;

  /// Decodes a `{"value": <number>, "basis": {...}}` object as a double.
  static Quantity<double> doubleFromJson(Map<String, Object?> json) {
    return Quantity(
      jsonDouble(json['value']),
      basis: Basis.fromJson(jsonMap(json['basis'])),
    );
  }

  /// Decodes a `{"value": <integer>, "basis": {...}}` object.
  static Quantity<int> intFromJson(Map<String, Object?> json) {
    return Quantity(
      jsonInt(json['value']),
      basis: Basis.fromJson(jsonMap(json['basis'])),
    );
  }

  /// The object form the Swift core reads and writes.
  Map<String, Object?> toJson() => {'basis': basis.toJson(), 'value': value};

  @override
  bool operator ==(Object other) =>
      other is Quantity<T> && other.value == value && other.basis == basis;

  @override
  int get hashCode => Object.hash(value, basis);

  @override
  String toString() => '$value ($basis)';
}
