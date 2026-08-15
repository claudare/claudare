import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';

class ReplicatedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;

  ReplicatedCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'replicated commands must produce at least one event',
      );
    }
  }
}

// TODO: this needs cleanup and more consideration.
bool replicatedCommandsEqual(ReplicatedCommand a, ReplicatedCommand b) =>
    a.commandId == b.commandId &&
    a.dependency == b.dependency &&
    a.encoded.kind == b.encoded.kind &&
    _bytesEqual(a.encoded.bytes, b.encoded.bytes) &&
    a.startedAt == b.startedAt &&
    a.completedAt == b.completedAt &&
    a.eventCount == b.eventCount;

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
