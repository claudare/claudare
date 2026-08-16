import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  group('CommandChanges', () {
    test('empty is valid', () async {
      final changes = CommandChanges(
        encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
        startedAt: timestamp,
        completedAt: timestamp,
        locks: [],
        events: [],
      );

      expect(changes.isValid(), isTrue);
    });

    test('no lock', () async {
      final changes = CommandChanges(
        encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
        startedAt: timestamp,
        completedAt: timestamp,
        locks: [],
        events: [
          EventAppend(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: timestamp,
          ),
          EventAppend(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: timestamp,
          ),
        ],
      );

      expect(changes.isValid(), isFalse);
    });

    test('no events', () async {
      final changes = CommandChanges(
        encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
        startedAt: timestamp,
        completedAt: timestamp,
        locks: [
          StreamLocalLock(streamId: 'test', originatingStreamVersion: 42),
        ],
        events: [],
      );

      expect(changes.isValid(), isFalse);
    });
  });
}
