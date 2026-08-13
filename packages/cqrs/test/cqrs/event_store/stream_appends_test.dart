import 'dart:typed_data' show Uint8List;

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:test/test.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';

void main() {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  group('StreamAppends', () {
    test('empty is valid', () async {
      final appends = StreamAppends.empty();

      expect(appends.isValid(), isTrue);
    });

    test('no lock', () async {
      final appends = StreamAppends(
        dependencies: EventDependency.empty(),
        localLocks: [],
        events: [
          StoredEventCommandWrite(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: timestamp,
          ),
          StoredEventCommandWrite(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: timestamp,
          ),
        ],
      );

      expect(appends.isValid(), isFalse);
    });

    test('no events', () async {
      final appends = StreamAppends(
        dependencies: EventDependency.empty(),
        localLocks: [
          StreamLocalLock(streamId: 'test', originatingStreamVersion: 42),
        ],
        events: [],
      );

      expect(appends.isValid(), isFalse);
    });
  });
}
