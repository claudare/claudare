/// unified way to deal with timestamps
/// essentially, this is a unix timestamp
class Timestamp implements Comparable<Timestamp> {
  /// unix value of the timestamp
  int value;

  Timestamp(this.value);

  Timestamp.fromDateTime(DateTime dateTime)
    : value = dateTime.millisecondsSinceEpoch;

  Timestamp.fromJson(String json) : value = int.parse(json);

  String toJson() {
    return value.toString();
  }

  // additional formattings go here
  String toISO8601() {
    final DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(value).toUtc();
    return dateTime.toIso8601String();
  }

  @override
  int compareTo(Timestamp other) {
    return value.compareTo(other.value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Timestamp && other.value == value;
  }

  bool operator >(Timestamp other) => value > other.value;
  bool operator <(Timestamp other) => value < other.value;
  bool operator >=(Timestamp other) => value >= other.value;
  bool operator <=(Timestamp other) => value <= other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Timestamp{value: $value}';
}
