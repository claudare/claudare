import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';

/// Commands are synced and they define a dependency boundary
class SyncCommand {
  final DeviceId deviceId;
  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final String? nackReason;
  final String? errorMessage;

  final List<SyncEvent> events;

  SyncCommand({
    required this.deviceId,
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,
    this.nackReason,
    this.errorMessage,
    required this.events,
  });
}

class SyncEvent {
  final int deviceSequence;
  final int causalSequence;

  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final DateTime createdAt;

  SyncEvent({
    required this.deviceSequence,
    required this.causalSequence,
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.metadata,
    required this.createdAt,
  });
}
