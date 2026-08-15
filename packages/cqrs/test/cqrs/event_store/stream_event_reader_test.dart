import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/stored_event_command_read.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:cqrs/src/cqrs/event_store/stream_event_reader.dart';
import 'package:test/test.dart';

void main() {
  group('StreamEventReader', () {
    late EventStore store;
    late StreamEventReader reader;

    const streamId = 'test';
    const pageSize = 2;

    setUp(() {
      store = EventStore(MemoryEventDatabase(), eventFetchPageSize: pageSize);
      reader = StreamEventReader(store, streamId);
    });

    test('handles empty result', () async {
      final events = await _scanAll(reader).toList();
      expect(events, isEmpty);
    });

    test('handles exact amount', () async {
      await _appendCount(store, pageSize);

      final events = await _scanAll(reader).toList();
      expect(events, hasLength(pageSize));
      expect(events[0].encodedEvent.kind, 'event-0');
      expect(events[1].encodedEvent.kind, 'event-1');
    });

    test('handles more', () async {
      await _appendCount(store, pageSize + 1);

      final events = await _scanAll(reader).toList();

      expect(events, hasLength(pageSize + 1));

      expect(events[0].encodedEvent.kind, 'event-0');
      expect(events[1].encodedEvent.kind, 'event-1');
      expect(events[2].encodedEvent.kind, 'event-2');
    });
  });
}

Stream<StoredEventCommandRead> _scanAll(StreamEventReader reader) async* {
  while (await reader.loadMore()) {
    for (final e in reader.currentPage) {
      yield e;
    }
  }
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
