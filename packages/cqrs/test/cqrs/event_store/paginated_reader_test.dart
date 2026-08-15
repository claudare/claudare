import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:cqrs/src/cqrs/event_store/paginated_read_result.dart';
import 'package:cqrs/src/cqrs/event_store/paginated_reader.dart';
import 'package:test/test.dart';

void main() {
  group('PaginatedReader', () {
    test('scans pages from the initial cursor in order', () async {
      final cursors = <int>[];
      final reader = PaginatedReader<int>((cursor) async {
        cursors.add(cursor);
        return switch (cursor) {
          5 => const PaginatedResult(data: [6, 7], next: 7),
          7 => const PaginatedResult(data: [8], next: null),
          _ => throw StateError('unexpected cursor $cursor'),
        };
      }, initialCursor: 5);

      expect(await reader.scan().toList(), [6, 7, 8]);
      expect(cursors, [5, 7]);
    });

    test('handles an empty first page', () async {
      final reader = PaginatedReader<int>((cursor) async {
        return const PaginatedResult(data: [], next: null);
      });

      expect(await reader.scan().toList(), isEmpty);
    });

    test('throws StateError when scanned twice', () async {
      final reader = PaginatedReader<int>((cursor) async {
        return const PaginatedResult(data: [1], next: null);
      });

      expect(await reader.scan().toList(), [1]);
      await expectLater(reader.scan().toList(), throwsStateError);
    });
  });

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
      StoredCommandWrite(
        encoded: EncodedCommand(kind: 'command-$i', bytes: Uint8List(0)),
        startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        completedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      StreamAppends(
        localLocks: [
          StreamLocalLock(streamId: 'test', originatingStreamVersion: i),
        ],
        events: [
          StoredEventCommandWrite(
            streamId: 'test',
            encodedEvent: EncodedEvent(kind: 'event-$i', bytes: Uint8List(0)),
            occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        ],
      ),
    );
  }
}
