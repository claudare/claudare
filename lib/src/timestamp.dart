import 'package:core/src/base58.dart';

const _stringLength = 11; // for u64

/// [TimestampGenerator] will ensure that timestamps are created in an
/// always increasing order. Same millisecond events will jump to the future by
/// 1 millisecond. This seems like a terrible hack, but I think it will work well.
class TimestampGenerator {
  int _last = 0;

  Timestamp next(Timestamp now) {
    if (now.value > _last) {
      _last = now.value;
      return now;
    }

    // otherwise fake timestamp by going a bit into the future
    _last++;

    // the timestamp is off by a whole 1 second!
    if (_last - now.value >= 1000) {
      throw Exception(
        'Timestamp ordering exhausted. Last $_last, now ${now.value}',
      );
    }

    return Timestamp(_last);
  }
}

class TimestampRange {
  final Timestamp start;
  final Timestamp end;

  TimestampRange(this.start, this.end) : assert(end > start);

  Map<String, dynamic> toJson() {
    return {'start': start.toJson(), 'end': end.toJson()};
  }

  factory TimestampRange.fromJson(Map<String, dynamic> json) {
    return TimestampRange(
      Timestamp.fromJson(json['start']),
      Timestamp.fromJson(json['end']),
    );
  }
}

/// A unified way to deal with timestamps.
/// Essentially, this is a unix timestamp.
class Timestamp implements Comparable<Timestamp> {
  /// unix millisecond value
  final int value;

  const Timestamp(this.value);

  const Timestamp.zero() : value = 0;

  Timestamp.fromDateTime(DateTime dateTime)
    : value = dateTime.millisecondsSinceEpoch;

  Timestamp.now() : value = DateTime.now().millisecondsSinceEpoch;

  // Additional formatting helper.
  // Only used for debugging pursposes.
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

  Timestamp operator +(Timestamp other) => Timestamp(value + other.value);
  Timestamp operator -(Timestamp other) => Timestamp(value - other.value);

  factory Timestamp.fromJson(String json) {
    return Timestamp.fromString(json);
  }

  String toJson() {
    return value.toString();
  }

  factory Timestamp.fromString(String str) {
    if (str.length != _stringLength) {
      throw FormatException('Timestamp is invalid, wrong length', str);
    }

    return Timestamp(Base58.fromString(str));
  }

  @override
  String toString() => Base58.toStringPadded(value, _stringLength);
}
