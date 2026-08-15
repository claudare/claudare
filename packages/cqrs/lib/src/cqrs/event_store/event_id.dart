import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event_store/command_id.dart';

class EventId extends Dot {
  final int index;

  EventId(super.deviceId, super.sequence, this.index) {
    if (index < 0) {
      throw FormatException('event index must be non-negative: $index');
    }
  }

  CommandId get commandId => CommandId(deviceId, sequence);

  @override
  List<int> toJson() => [deviceId, sequence, index];

  factory EventId.fromJson(List<dynamic> json) {
    if (json.length != 3) {
      throw const FormatException(
        'event id must contain device id, sequence, and index',
      );
    }
    return EventId(json[0] as int, json[1] as int, json[2] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is EventId &&
          deviceId == other.deviceId &&
          sequence == other.sequence &&
          index == other.index;

  @override
  int get hashCode => Object.hash(deviceId, sequence, index);

  @override
  String toString() =>
      'EventId(deviceId: $deviceId, sequence: $sequence, index: $index)';
}
