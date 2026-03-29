import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';

/// TODO: this needs to have dependencies?
class StoredCommandWrite {
  final String applicationId;
  final DeviceId deviceId;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final CommandResult result;

  const StoredCommandWrite({
    required this.applicationId,
    required this.deviceId,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.result,
  });
}

/// [StoredCommandRead] is used for iterating events inside the commands
class StoredCommandRead {
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final CommandResult result;

  const StoredCommandRead({
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,

    required this.result,
  });
}
