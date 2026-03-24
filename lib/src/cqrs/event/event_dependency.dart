import 'package:core/src/cqrs/device_id.dart';

class EventDependency {
  final Map<DeviceId, int> _vector = {};

  void add(DeviceId deviceId, int causalSequence) {
    if (causalSequence > (_vector[deviceId] ?? 0)) {
      _vector[deviceId] = causalSequence;
    }
  }

  // serialize as entries
  List<List<dynamic>> toJson() =>
      _vector.entries.map((e) => [e.key.toJson(), e.value]).toList();

  // ugly but okay
  static EventDependency fromJson(List<List<dynamic>> json) =>
      EventDependency()
        .._vector.addAll(
          Map.fromEntries(
            json.map(
              (e) => MapEntry(DeviceId.fromJson(e[0] as int), e[1] as int),
            ),
          ),
        );
}
