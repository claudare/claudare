import 'package:cqrs/cqrs.dart';

/// A message exchanged within one replication session.
sealed class ReplicationMessage {
  const ReplicationMessage();

  Map<String, dynamic> toJson() => switch (this) {
    ReplicationMessageDependency(:final version) => {
      'type': 'dependency',
      'dependencies': version.toJson(),
    },
    ReplicationMessageCommand(:final command) => {
      'type': 'command',
      'command': command.toJson(),
    },
    ReplicationMessageCommandAck(:final commandId) => {
      'type': 'commandAck',
      'commandId': commandId.toJson(),
    },
  };

  factory ReplicationMessage.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'dependency' => ReplicationMessageDependency(
          CommandDependency.fromJson(
            json['dependencies'] as Map<String, dynamic>,
          ),
        ),
        'command' => ReplicationMessageCommand(
          StoredCommand.fromJson(json['command'] as Map<String, dynamic>),
        ),
        'commandAck' => ReplicationMessageCommandAck(
          CommandId.fromJson(json['commandId'] as List<dynamic>),
        ),
        _ => throw FormatException(
          'Unknown replication message type: ${json['type']}',
        ),
      };
}

/// Subscribes to missing and future commands using the receiver's history.
class ReplicationMessageDependency extends ReplicationMessage {
  final CommandDependency version;

  const ReplicationMessageDependency(this.version);
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
