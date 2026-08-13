import 'package:cqrs/src/cqrs/command/command_result.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';

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
