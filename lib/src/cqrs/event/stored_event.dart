import 'package:core/src/device_id.dart';

/// events to write to the database from commands
class StoredEventCommandWrite {
  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final DateTime createdAt;

  const StoredEventCommandWrite({
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.metadata,
    required this.createdAt,
  });
}

/// events that are read from event store for the command processing
/// this provides more in-depth to information to attach dependencies
class StoredEventCommandRead {
  final DeviceId deviceId;
  final int causalSequence;
  final String kind;
  final String detail;
  final String metadata;
  final DateTime createdAt;

  const StoredEventCommandRead({
    required this.deviceId,
    required this.causalSequence,
    required this.kind,
    required this.detail,
    required this.metadata,
    required this.createdAt,
  });
}

/// [StoredEventProjectionRead] is for rebuilding projections
class StoredEventProjectionRead {
  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final DateTime createdAt;
  final int localSequence;

  const StoredEventProjectionRead({
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.metadata,
    required this.createdAt,
    required this.localSequence,
  });
}
