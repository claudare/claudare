import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';

class LogCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;
  final int logPosition;

  LogCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
    required this.logPosition,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'log commands must produce at least one event',
      );
    }
  }

  StagedCommand toStagedCommand() => StagedCommand(
    commandId: commandId,
    dependency: dependency,
    encoded: encoded,
    startedAt: startedAt,
    completedAt: completedAt,
    eventCount: eventCount,
  );

  factory LogCommand.fromStagedCommand(
    StagedCommand command, {
    required int logPosition,
  }) => LogCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    encoded: command.encoded,
    startedAt: command.startedAt,
    completedAt: command.completedAt,
    eventCount: command.eventCount,
    logPosition: logPosition,
  );
}
