import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';

/// A complete command and its ordered events at the replication boundary.
class CommandBundle {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final List<BundledEvent> events;

  const CommandBundle({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.events,
  });

  bool get isValid => events.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandBundle &&
          other.runtimeType == runtimeType &&
          commandId == other.commandId &&
          dependency == other.dependency &&
          occuredAt == other.occuredAt &&
          _eventsEqual(events, other.events);

  @override
  int get hashCode =>
      Object.hash(commandId, dependency, occuredAt, Object.hashAll(events));
}

/// An event in a [CommandBundle], positioned by its list index.
class BundledEvent {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const BundledEvent({
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is BundledEvent &&
          streamPath == other.streamPath &&
          encodedEvent.kind == other.encodedEvent.kind &&
          _bytesEqual(encodedEvent.bytes, other.encodedEvent.bytes) &&
          occuredAt == other.occuredAt;

  @override
  int get hashCode => Object.hash(
    streamPath,
    encodedEvent.kind,
    Object.hashAll(encodedEvent.bytes),
    occuredAt,
  );
}

bool _eventsEqual(List<BundledEvent> a, List<BundledEvent> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
