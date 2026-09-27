import 'package:cqrs/cqrs.dart';

sealed class ReplicationMessage {
  const ReplicationMessage();
}

class ReplicationMessageDependency extends ReplicationMessage {
  final CommandDependency dependencies;

  const ReplicationMessageDependency(this.dependencies);
}

class ReplicationMessageCommand extends ReplicationMessage {
  final StoredCommand command;

  const ReplicationMessageCommand(this.command);
}

class ReplicationMessageCommandAck extends ReplicationMessage {
  final CommandId commandId;

  const ReplicationMessageCommandAck(this.commandId);
}
