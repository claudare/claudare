import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  group('CommandChanges', () {
    test('empty is valid', () {
      final changes = _changes();

      expect(changes.isValid(), isTrue);
    });

    test('rejects events without a lock', () {
      final changes = _changes(eventPaths: ['test', 'test']);

      expect(changes.isValid(), isFalse);
    });

    test('allows locks without events', () {
      final changes = _changes(lockPaths: ['test']);

      expect(changes.isValid(), isTrue);
    });

    test('allows locks for streams without appended events', () {
      final changes = _changes(
        lockPaths: ['read', 'write'],
        eventPaths: ['write'],
      );

      expect(changes.isValid(), isTrue);
    });

    test('allows multiple events per lock', () {
      final changes = _changes(
        lockPaths: ['one', 'two'],
        eventPaths: ['one', 'two', 'one'],
      );

      expect(changes.isValid(), isTrue);
    });

    test('rejects an event missing its own stream lock', () {
      final changes = _changes(
        lockPaths: ['locked'],
        eventPaths: ['locked', 'unlocked'],
      );

      expect(changes.isValid(), isFalse);
    });

    for (final scenario in [
      (name: 'with events', eventPaths: ['duplicate']),
      (name: 'without events', eventPaths: ['other']),
      (name: 'in an empty batch', eventPaths: <String>[]),
    ]) {
      test('rejects duplicate locks ${scenario.name}', () {
        final changes = _changes(
          lockPaths: ['duplicate', 'duplicate', 'other'],
          eventPaths: scenario.eventPaths,
        );

        expect(changes.isValid(), isFalse);
      });
    }
  });
}

CommandChanges _changes({
  List<String> lockPaths = const [],
  List<String> eventPaths = const [],
}) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return CommandChanges(
    actor: 'test-actor',
    dependency: CommandDependency(),
    occuredAt: timestamp,
    locks: [
      for (final path in lockPaths)
        StreamLock(streamPath: path, originatingStreamVersion: 42),
    ],
    events: [
      for (final path in eventPaths)
        EventAppend(
          streamPath: path,
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: timestamp,
        ),
    ],
  );
}
