import 'package:core/src/cqrs/device_id.dart';
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
  final DeviceId deviceId;
  final int causalSequence;
  final int localVersion;

  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const StoredEventCommandRead({
    required this.deviceId,
    required this.causalSequence,
    required this.localVersion,

    required this.encodedEvent,
    required this.occuredAt,
  });
}

/// [StoredEventProjectionRead] is for rebuilding projections
class StoredEventProjectionRead {
  final int localSequence;
  final int localVersion;

  final String streamId;
  final String kind;
  final String detail;
  final DateTime occuredAt;

  const StoredEventProjectionRead({
    required this.localSequence,
    required this.localVersion,

    required this.streamId,
    required this.kind,
    required this.detail,
    required this.occuredAt,
  });

  EventMetadata get eventMetadata => EventMetadata(
    occuredAt: occuredAt,
    localSequence: localSequence,
    localVersion: localVersion,
  );
}
