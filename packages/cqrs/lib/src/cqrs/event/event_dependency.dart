import 'package:common/common.dart';

/// [EventDependency] keeps track of the events that must be replicated before
/// new events are applied. This is a key on keeping correct order during sync.
/// A vector is used and stored.
/// TODO: rename to EventDependencies
class EventDependency {
  final Map<DeviceId, int> _vector;

  const EventDependency(this._vector);

  EventDependency.empty() : _vector = {};

  void add(DeviceIdSequencePair causalSequence) {
    if (causalSequence.sequence > (_vector[causalSequence.deviceId] ?? 0)) {
      _vector[causalSequence.deviceId] = causalSequence.sequence;
    }
  }

  void merge(EventDependency other) {
    for (final entry in other._vector.entries) {
      if (entry.value > (_vector[entry.key] ?? 0)) {
        _vector[entry.key] = entry.value;
      }
    }
  }

  int value(DeviceId deviceId) => _vector[deviceId] ?? 0;

  Map<DeviceId, int> get vector => _vector;

  // serialize as entries
  List<List<dynamic>> toJson() =>
      _vector.entries.map((e) => [e.key.toJson(), e.value]).toList();

  // ugly but okay
  static EventDependency fromJson(List<List<dynamic>> json) => EventDependency(
    Map.fromEntries(
      json.map((e) => MapEntry(DeviceId.fromJson(e[0] as int), e[1] as int)),
    ),
  );

  @override
  String toString() => 'EventDependency(vector: $_vector)';
}
