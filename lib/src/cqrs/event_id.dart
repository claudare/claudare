import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/timestamp.dart';

class EventIdMin {
  final int localSequence;

  const EventIdMin(this.localSequence);
}

/// [EventId] is a key foundational concept for ordering events globally,
/// syncing in order, and ordering inside the Streams.
/// This weak causality is important for offline-first operation.
/// As for all Ids (except for unassigned device), zero is a null value
/// For now this is not used
class EventId {
  /// auto incrementing sequence for the view of global events on this device
  /// (localSequence)
  final int localSequence;

  /// device that issued the id
  final DeviceId deviceId;

  /// auto incrementing sequence for the given device
  /// for replication
  /// (deviceSequence + deviceId)
  final int deviceSequence;

  /// globally consistent ordering like lamport clock
  /// for reliable replays??? This is not really needed?
  /// (casualSequence + deviceId)
  final int causalSequence;

  const EventId({
    required this.localSequence,
    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
  }) : assert(localSequence > 0),
       assert(deviceSequence > 0),
       assert(causalSequence > 0);

  EventId.first(this.deviceId, Timestamp? timestamp)
    : localSequence = 1,
      deviceSequence = 1,
      causalSequence = 1;

  toJson() {
    return {
      'localSequence': localSequence,
      'deviceId': deviceId.toJson(),
      'deviceSequence': deviceSequence,
      'causalSequence': causalSequence,
    };
  }

  EventId.fromJson(Map<String, dynamic> json)
    : localSequence = json['localSequence'],
      deviceId = DeviceId.fromJson(json['deviceId']),
      deviceSequence = json['deviceSequence'],
      causalSequence = json['causalSequence'];
}
