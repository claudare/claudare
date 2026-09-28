import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';

/// A message exchanged within one replication session.
sealed class ReplicationMessage {
  const ReplicationMessage();
}

/// Subscribes to missing and future commands using the receiver's history.
class ReplicationMessageDependency extends ReplicationMessage {
  final CommandDependency dependencies;

  const ReplicationMessageDependency(this.dependencies);
}

/// A complete command to save before acknowledging.
class ReplicationMessageCommand extends ReplicationMessage {
  final StoredCommand command;

  const ReplicationMessageCommand(this.command);
}

/// Confirms that saving the outstanding command succeeded.
class ReplicationMessageCommandAck extends ReplicationMessage {
  final CommandId commandId;

  const ReplicationMessageCommandAck(this.commandId);
}
