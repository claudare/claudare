import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:test/test.dart';

void main() {
  group('EventStore stream reader', () {
    late EventStore store;

    const pageSize = 2;

    setUp(() {
      store = EventStore(MemoryEventDatabase(), eventFetchPageSize: pageSize);
    });

    test('handles empty result', () async {
      expect(await store.getStreamReader('test').scan().toList(), isEmpty);
    });

    test('handles exact page size', () async {
      await _appendCount(store, pageSize);

      final events = await store.getStreamReader('test').scan().toList();
      expect(events, hasLength(pageSize));
      expect(events[0].encodedEvent.kind, 'event-0');
      expect(events[1].encodedEvent.kind, 'event-1');
    });

    test('handles multiple pages', () async {
      await _appendCount(store, pageSize + 1);

      final events = await store.getStreamReader('test').scan().toList();
      expect(events, hasLength(pageSize + 1));
      expect(events.map((event) => event.encodedEvent.kind), [
        'event-0',
        'event-1',
        'event-2',
      ]);
    });
  });
}

Future<void> _appendCount(EventStore store, int count) async {
  for (var i = 0; i < count; i++) {
    await store.saveChanges(
      CommandChanges(
        encoded: EncodedCommand(kind: 'command-$i', bytes: Uint8List(0)),
        startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        completedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        locks: [
          StreamLocalLock(streamPath: 'test', originatingStreamVersion: i),
        ],
        events: [
          EventAppend(
            streamPath: 'test',
            encodedEvent: EncodedEvent(kind: 'event-$i', bytes: Uint8List(0)),
            occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        ],
      ),
    );
  }
}
