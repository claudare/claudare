import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';

/// events that are read from event store for the command processing
/// this provides more in-depth to information to attach dependencies
class StoredEventCommandRead {
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final DeviceId deviceId;
  final int causalSequence;
  final int streamVersion;

  const StoredEventCommandRead({
    required this.encodedEvent,
    required this.occuredAt,

    required this.deviceId,
    required this.causalSequence,
    required this.streamVersion,
  });
}
