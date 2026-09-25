import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';

class LogCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final int eventCount;
  final int logPosition;

  LogCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
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
    occuredAt: occuredAt,
    eventCount: eventCount,
  );

  factory LogCommand.fromStagedCommand(
    StagedCommand command, {
    required int logPosition,
  }) => LogCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    occuredAt: command.occuredAt,
    eventCount: command.eventCount,
    logPosition: logPosition,
  );
}
