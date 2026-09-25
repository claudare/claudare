import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';

class StagedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final int eventCount;

  StagedCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.eventCount,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'staged commands must produce at least one event',
      );
    }
  }
}

// TODO: this needs cleanup and more consideration.
bool stagedCommandsEqual(StagedCommand a, StagedCommand b) =>
    a.commandId == b.commandId &&
    a.dependency == b.dependency &&
    a.occuredAt == b.occuredAt &&
    a.eventCount == b.eventCount;
