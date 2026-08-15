import 'dot.dart';

/// A compact contiguous causal history indexed by device.
class VersionVector {
  final Map<int, int> _values;

  VersionVector([Map<int, int> values = const {}])
    : _values = Map.unmodifiable(_validated(values));

  static Map<int, int> _validated(Map<int, int> values) {
    for (final entry in values.entries) {
      if (entry.value < 0) {
        throw FormatException(
          'version-vector sequence must be non-negative: ${entry.value}',
        );
      }
    }
    return Map.of(values)..removeWhere((_, value) => value == 0);
  }

  int value(int deviceId) => _values[deviceId] ?? 0;

  Map<int, int> get values => _values;

  bool contains(VersionVector dependency) {
    for (final entry in dependency._values.entries) {
      if (value(entry.key) < entry.value) return false;
    }
    return true;
  }

  VersionVector advance(Dot dot) {
    final expected = value(dot.deviceId) + 1;
    if (dot.sequence != expected) {
      throw StateError(
        'out-of-order dot ${dot.sequence}, expected $expected for ${dot.deviceId}',
      );
    }
    return VersionVector({..._values, dot.deviceId: dot.sequence});
  }

  List<List<int>> toJson() {
    final entries = _values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries) [entry.key, entry.value],
    ];
  }

  factory VersionVector.fromJson(List<dynamic> json) {
    final values = <int, int>{};
    for (final value in json) {
      final pair = value as List<dynamic>;
      if (pair.length != 2) {
        throw const FormatException(
          'version-vector entry must contain device id and sequence',
        );
      }
      final deviceId = pair[0] as int;
      if (values.containsKey(deviceId)) {
        throw FormatException('duplicate version-vector device: $deviceId');
      }
      values[deviceId] = pair[1] as int;
    }
    return VersionVector(values);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VersionVector || _values.length != other._values.length) {
      return false;
    }
    return _values.entries.every(
      (entry) => other.value(entry.key) == entry.value,
    );
  }

  @override
  int get hashCode {
    var result = 0;
    for (final pair in toJson()) {
      result = Object.hash(result, pair[0], pair[1]);
    }
    return result;
  }

  @override
  String toString() => 'VersionVector(${toJson()})';
}
