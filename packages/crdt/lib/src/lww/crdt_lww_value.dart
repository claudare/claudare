import 'crdt_lww_change.dart';

class CrdtLwwValue<T> {
  T _value;
  DateTime _time;

  CrdtLwwValue(this._value, this._time);

  // maybe this should be most negative value?
  CrdtLwwValue.zero(T value)
    : this(value, DateTime.fromMillisecondsSinceEpoch(0));

  Map<String, dynamic> toJson() => {
    'value': _value,
    'time': _time.millisecondsSinceEpoch,
  };

  factory CrdtLwwValue.fromJson(Map<String, dynamic> json) => CrdtLwwValue(
    json['value'],
    DateTime.fromMillisecondsSinceEpoch(json['time']),
  );

  T get value => _value;

  void applyChange(CrdtLwwChange<T> change) {
    if (change.unixMillis.compareTo(_time) > 0) {
      _value = change.value;
      _time = change.unixMillis;
    }
  }
}
