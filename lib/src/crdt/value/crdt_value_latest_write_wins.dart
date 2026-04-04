import 'package:core/src/crdt/value/crdt_value_date_time_pair.dart';

class CrdtValueLatestWriteWins<T> {
  final T value;
  final DateTime occurredAt;

  const CrdtValueLatestWriteWins(this.value, this.occurredAt);
  CrdtValueLatestWriteWins.zero(T value)
    : this(value, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

  CrdtValueLatestWriteWins<T> merge(
    T incomingValue,
    DateTime incomingOccurredAt,
  ) {
    // if new value is in the past, ignore it
    if (incomingOccurredAt.compareTo(occurredAt) < 0) {
      return this;
    }

    return CrdtValueLatestWriteWins(incomingValue, incomingOccurredAt);
  }

  CrdtValueLatestWriteWins<T> mergePair(CrdtValueDateTimePair<T> incomingPair) {
    return merge(incomingPair.value, incomingPair.occurredAt);
  }
}
