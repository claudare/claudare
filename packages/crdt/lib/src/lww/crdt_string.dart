import 'package:crdt/src/lww/crdt_string_change.dart';

/// Last-Write-Wins (LWW) CRDT string value.
class CrdtString {
  String _value = '';
  String _actor = '';
  int? _time;

  CrdtString();

  Map<String, dynamic> toJson() => {
    'value': _value,
    'actor': _actor,
    'time': _time,
  };

  factory CrdtString.fromJson(Map<String, dynamic> json) {
    final v = CrdtString();
    v._value = json['value'] as String;
    v._actor = json['actor'] as String;
    v._time = json['time'] as int?;
    return v;
  }

  String get value => _time != null ? _value : '';

  void applyChange(CrdtStringChange change) {
    if (_time == null) {
      _apply(change);
      return;
    }

    if (_compareTo(change) < 0) {
      _apply(change);
    }
  }

  int _compareTo(CrdtStringChange change) {
    final times = _time!.compareTo(change.time.millisecondsSinceEpoch);
    if (times == 0) {
      final actors = _actor.compareTo(change.actor);
      if (actors == 0) {
        // very unlikely, but idk what else to do
        return _value.compareTo(change.value);
      }
      return actors;
    }
    return times;
  }

  void _apply(CrdtStringChange change) {
    _value = change.value;
    _actor = change.actor;
    _time = change.time.millisecondsSinceEpoch;
  }
}
