import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:common/common.dart';

/// TODO: this needs to have dependencies?
class StoredCommandWrite {
  final DeviceId deviceId;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final CommandResult result;

  const StoredCommandWrite({
    required this.deviceId,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.result,
  });
}
