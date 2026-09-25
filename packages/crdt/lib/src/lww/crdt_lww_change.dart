class CrdtLwwChange<T> {
  final T value;
  final DateTime unixMillis;

  const CrdtLwwChange(this.value, this.unixMillis);

  CrdtLwwChange.zero(T value)
    : this(value, DateTime.fromMillisecondsSinceEpoch(0));
}
