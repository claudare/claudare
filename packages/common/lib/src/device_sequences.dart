import 'device_id.dart';
import 'device_id_sequence_pair.dart';

/// [DeviceSequences] keeps track of the autoincrementing sequences for each device.
/// Used in sync to make sure that all commands and events are applied in device-local order.
class DeviceSequences {
  final Map<DeviceId, int> _vector = {};

  bool isInOrder(DeviceIdSequencePair deviceSequence) {
    final current = _vector[deviceSequence.deviceId] ?? 0;
    return deviceSequence.sequence == current + 1;
  }

  void apply(DeviceIdSequencePair deviceSequence) {
    if (!isInOrder(deviceSequence)) {
      throw StateError('Out of order sequence');
    }
    _vector[deviceSequence.deviceId] = deviceSequence.sequence;
  }

  void reset() {
    _vector.clear();
  }

  // gets next autoincremental value
  // use only for the current device
  int nextSequence(DeviceId deviceId) {
    final nextValue = (_vector[deviceId] ?? 0) + 1;
    _vector[deviceId] = nextValue;
    return nextValue;
  }

  int value(DeviceId deviceId) => _vector[deviceId] ?? 0;

  Map<DeviceId, int> get vector => _vector;

  // serialize as entries
  List<List<dynamic>> toJson() =>
      _vector.entries.map((e) => [e.key.toJson(), e.value]).toList();

  // ugly but okay
  static DeviceSequences fromJson(List<List<dynamic>> json) => DeviceSequences()
    .._vector.addAll(
      Map.fromEntries(
        json.map((e) => MapEntry(DeviceId.fromJson(e[0] as int), e[1] as int)),
      ),
    );
}
