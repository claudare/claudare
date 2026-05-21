import 'dart:typed_data' show Uint8List;

import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event_command_write.dart';
import 'package:test/test.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';

void main() {
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
            occuredAt: DateTime.now(),
          ),
          StoredEventCommandWrite(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: DateTime.now(),
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
