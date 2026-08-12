import 'device_id.dart';

class DeviceIdSequencePair {
  final DeviceId deviceId;
  final int sequence;

  const DeviceIdSequencePair(this.deviceId, this.sequence);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceIdSequencePair &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          sequence == other.sequence;

  @override
  int get hashCode => deviceId.hashCode ^ sequence.hashCode;

  @override
  String toString() =>
      'DeviceIdSequencePair(deviceId: $deviceId, sequence: $sequence)';
}
