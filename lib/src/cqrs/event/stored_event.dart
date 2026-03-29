import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';

/// events to write to the database from commands
class StoredEventCommandWrite {
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const StoredEventCommandWrite({
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
  });
}

/// events that are read from event store for the command processing
/// this provides more in-depth to information to attach dependencies
class StoredEventCommandRead {
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final DeviceId deviceId;
  final int causalSequence;
  final int localVersion;

  const StoredEventCommandRead({
    required this.encodedEvent,
    required this.occuredAt,

    required this.deviceId,
    required this.causalSequence,
    required this.localVersion,
  });
}

/// [StoredEventProjectionRead] is for rebuilding projections
class StoredEventProjectionRead {
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final int localSequence;

  const StoredEventProjectionRead({
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,

    required this.localSequence,
  });

  EventMetadata get eventMetadata =>
      EventMetadata(occuredAt: occuredAt, localSequence: localSequence);
}
