class CrdtValueDateTimePair<V> {
  final V value;
  final DateTime occurredAt;

  const CrdtValueDateTimePair(this.value, this.occurredAt);

  CrdtValueDateTimePair.zero(V value)
    : this(value, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
}
