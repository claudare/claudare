import 'dart:convert';

import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/command/command_dependency.dart';

/// A command with its ordered events and blob references for replication.
class StoredCommand {
  final CommandId commandId;
  final CommandDependency dependency;
  final DateTime occuredAt;
  final List<StoredCommandEvent> events;
  final List<String> blobIds;

  const StoredCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.events,
    required this.blobIds,
  });

  Map<String, dynamic> toJson() => {
    'commandId': commandId.toJson(),
    'dependency': dependency.toJson(),
    'occuredAt': occuredAt.toUtc().toIso8601String(),
    'events': [for (final event in events) event.toJson()],
    'blobIds': blobIds,
  };

  factory StoredCommand.fromJson(Map<String, dynamic> json) => StoredCommand(
    commandId: CommandId.fromJson(json['commandId'] as List<dynamic>),
    dependency: CommandDependency.fromJson(
      json['dependency'] as Map<String, dynamic>,
    ),
    occuredAt: DateTime.parse(json['occuredAt'] as String),
    blobIds: List<String>.from(json['blobIds'] as List),
    events: [
      for (final event in json['events'] as List<dynamic>)
        StoredCommandEvent.fromJson(event as Map<String, dynamic>),
    ],
  );

  @override
  String toString() =>
      'StoredCommand(commandId: $commandId, dependency: $dependency, '
      'occuredAt: $occuredAt, events: $events)';
}

/// An event in a [StoredCommand], positioned by its list index.
class StoredCommandEvent {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const StoredCommandEvent({
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

  factory StoredCommandEvent.fromJson(Map<String, dynamic> json) =>
      StoredCommandEvent(
        streamPath: json['streamPath'] as String,
        encodedEvent: EncodedEvent(
          kind: json['kind'] as String,
          bytes: base64Decode(json['bytes'] as String),
        ),
        occuredAt: DateTime.parse(json['occuredAt'] as String),
      );

  @override
  String toString() =>
      'StoredCommandEvent(streamPath: $streamPath, '
      'kind: ${encodedEvent.kind}, byteLength: ${encodedEvent.bytes.length}, '
      'occuredAt: $occuredAt)';
}
