import 'package:core/event_store.dart';

class StoredCommandFull {
  // minimum serialized data
  final String kind;
  final String detail;
  final DateTime completedAt;

  // result
  final String? nackReason;
  final Exception? exception;

  // all id stuffs. This replaces the uuid and sequence number in js implementation
  final EventId commandId;

  const StoredCommandFull({
    required this.kind,
    required this.detail,
    required this.completedAt,
    required this.nackReason,
    required this.exception,
    required this.commandId,
  });
}

// this is sent to the database to insert
// the database knows the
class StoredCommandMin {
  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;

  const StoredCommandMin({
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
  });
}

class StoredCommandResult {
  final String? nackReason;
  final Exception? exception; // can this be error too... this is any failure

  const StoredCommandResult({
    required this.nackReason,
    required this.exception,
  });
}
