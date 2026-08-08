import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';

/// events that are read from event store for the command processing
/// this provides more in-depth information for dependency definition
class StoredEventCommandRead {
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final DeviceIdSequencePair causalPair;
  final int streamVersion;

  const StoredEventCommandRead({
    required this.encodedEvent,
    required this.occuredAt,

    required this.causalPair,
    required this.streamVersion,
  });
}
