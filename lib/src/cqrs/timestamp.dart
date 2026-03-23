/// A unified way to deal with timestamps.
/// Essentially, this is a unix timestamp.
class Timestamp implements Comparable<Timestamp> {
  /// unix millisecond value
  final DateTime value;

  const Timestamp(this.value);

  Timestamp.now() : value = DateTime.now();

  Timestamp.fromISO8601(String iso8601)
    : value = DateTime.parse(iso8601).toUtc();

  Timestamp.fromUnix(int unix)
    : value = DateTime.fromMillisecondsSinceEpoch(unix).toUtc();

  // Additional formatting helper.
  // Only used for debugging pursposes.
  String toISO8601() {
    return value.toIso8601String();
  }

  int toUnix() {
    return value.millisecondsSinceEpoch;
  }

  /// An easy-on-the-eyes string representation.
  /// Use for debug/logging
  @override
  String toString() {
    return '${value.year}-${value.month}-${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  }

  // for now JSON stringification is an iso timestamp
  // in the future binary packing will be done
  toJson() {
    return toISO8601();
  }

  Timestamp.fromJson(String iso8601) : value = DateTime.parse(iso8601).toUtc();

  @override
  int compareTo(Timestamp other) {
    return value.compareTo(other.value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Timestamp && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}
