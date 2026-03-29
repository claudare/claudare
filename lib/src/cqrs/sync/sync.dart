import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';

/// Commands are synced and they define a dependency boundary
/// This is the whole payload though, not just the command
/// its command + commandResult + dependencies + events!
class SyncCommand {
  final DeviceIdSequencePair deviceSequence;

  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final String? nackReason;
  final String? errorMessage;

  final List<SyncEvent> events;

  SyncCommand({
    required this.deviceSequence,
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
  final DeviceId deviceId;
  final int deviceSequence;
  final int causalSequence;

  final String streamId;
  final String kind;
  final String detail;
  final DateTime occuredAt;

  SyncEvent({
    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.occuredAt,
  });
}
