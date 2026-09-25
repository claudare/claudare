import 'dart:convert';
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

  Map<String, dynamic> toJson() => {
    'commandId': commandId.toJson(),
    'dependency': dependency.toJson(),
    'occuredAt': occuredAt.toUtc().toIso8601String(),
    'events': [for (final event in events) event.toJson()],
  };

  factory CommandBundle.fromJson(Map<String, dynamic> json) => CommandBundle(
    commandId: CommandId.fromJson(json['commandId'] as List<dynamic>),
    dependency: VersionVector.fromJson(json['dependency'] as List<dynamic>),
    occuredAt: DateTime.parse(json['occuredAt'] as String),
    events: [
      for (final event in json['events'] as List<dynamic>)
        BundledEvent.fromJson(event as Map<String, dynamic>),
    ],
  );

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

  @override
  String toString() =>
      'CommandBundle(commandId: $commandId, '
      'dependency: $dependency, occuredAt: $occuredAt, events: $events)';
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

  Map<String, dynamic> toJson() => {
    'streamPath': streamPath,
    'kind': encodedEvent.kind,
    'bytes': base64Encode(encodedEvent.bytes),
    'occuredAt': occuredAt.toUtc().toIso8601String(),
  };

  factory BundledEvent.fromJson(Map<String, dynamic> json) => BundledEvent(
    streamPath: json['streamPath'] as String,
    encodedEvent: EncodedEvent(
      kind: json['kind'] as String,
      bytes: base64Decode(json['bytes'] as String),
    ),
    occuredAt: DateTime.parse(json['occuredAt'] as String),
  );

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

  @override
  String toString() =>
      'BundledEvent(streamPath: $streamPath, '
      'kind: ${encodedEvent.kind}, byteLength: ${encodedEvent.bytes.length}, '
      'occuredAt: $occuredAt)';
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
