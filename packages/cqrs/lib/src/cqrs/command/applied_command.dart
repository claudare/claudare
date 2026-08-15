import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';

class AppliedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;
  final int localSequence;

  AppliedCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
    required this.localSequence,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'applied commands must produce at least one event',
      );
    }
  }

  ReplicatedCommand toReplicatedCommand() => ReplicatedCommand(
    commandId: commandId,
    dependency: dependency,
    encoded: encoded,
    startedAt: startedAt,
    completedAt: completedAt,
    eventCount: eventCount,
  );

  factory AppliedCommand.fromReplicatedCommand(
    ReplicatedCommand command, {
    required int localSequence,
  }) => AppliedCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    encoded: command.encoded,
    startedAt: command.startedAt,
    completedAt: command.completedAt,
    eventCount: command.eventCount,
    localSequence: localSequence,
  );
}
