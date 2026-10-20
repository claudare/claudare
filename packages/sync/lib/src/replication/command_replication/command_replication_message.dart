import 'package:cqrs/cqrs.dart';

/// A message exchanged within one replication session.
sealed class CommandReplicationMessage {
  const CommandReplicationMessage();

  Map<String, dynamic> toJson() => switch (this) {
    CommandReplicationMessageDependency(:final version) => {
      'type': 'dependency',
      'dependencies': version.toJson(),
    },
    CommandReplicationMessageCommand(:final command) => {
      'type': 'command',
      'command': command.toJson(),
    },
    CommandReplicationMessageCommandAck(:final commandId) => {
      'type': 'commandAck',
      'commandId': commandId.toJson(),
    },
  };

  /// Rejects malformed JSON, including nested command fields, with [FormatException].
  factory CommandReplicationMessage.fromJson(Object? value) {
    try {
      final json = value as Map<String, dynamic>;
      return switch (json['type']) {
        'dependency' => CommandReplicationMessageDependency(
          CommandDependency.fromJson(
            json['dependencies'] as Map<String, dynamic>,
          ),
        ),
        'command' => CommandReplicationMessageCommand(
          StoredCommand.fromJson(json['command'] as Map<String, dynamic>),
        ),
        'commandAck' => CommandReplicationMessageCommandAck(
          CommandId.fromJson(json['commandId'] as List<dynamic>),
        ),
        _ => throw FormatException(
          'Unknown replication message type: ${json['type']}',
        ),
      };
    } on TypeError catch (_, stack) {
      // Nested CQRS decoders use casts. Translate only at this wire boundary.
      Error.throwWithStackTrace(
        const FormatException('Invalid replication message fields'),
        stack,
      );
    }
  }
}

/// Subscribes to missing and future commands using the receiver's history.
class CommandReplicationMessageDependency extends CommandReplicationMessage {
  final CommandDependency version;

  const CommandReplicationMessageDependency(this.version);
}

/// A complete command to save before acknowledging.
class CommandReplicationMessageCommand extends CommandReplicationMessage {
  final StoredCommand command;

  const CommandReplicationMessageCommand(this.command);
}

/// Confirms that saving the outstanding command succeeded.
class CommandReplicationMessageCommandAck extends CommandReplicationMessage {
  final CommandId commandId;

  const CommandReplicationMessageCommandAck(this.commandId);
}
