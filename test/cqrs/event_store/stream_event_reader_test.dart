import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/event_store/stream_event_reader.dart';
import 'package:test/test.dart';

void main() {
  group('StreamEventReader', () {
    late MemoryEventStore store;
    late StreamEventReader reader;

    const streamId = 'test';
    const pageSize = 2;

    setUp(() {
      store = MemoryEventStore(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      reader = StreamEventReader(store, pageSize, streamId);
    });

    test('handles empty result', () async {
      final events = await _scanAll(reader).toList();
      expect(events, isEmpty);
    });

    test('handles exact amount', () async {
      _appendCount(store, pageSize);

      final events = await _scanAll(reader).toList();
      expect(events, hasLength(pageSize));
      expect(events[0].kind, 'event-0');
      expect(events[1].kind, 'event-1');
    });

    test('handles more', () async {
      _appendCount(store, pageSize + 1);

      final events = await _scanAll(reader).toList();

      expect(events, hasLength(pageSize + 1));

      expect(events[0].kind, 'event-0');
      expect(events[1].kind, 'event-1');
      expect(events[2].kind, 'event-2');
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

_appendCount(MemoryEventStore store, int count) {
  for (var i = 0; i < count; i++) {
    store.testInsertEvent(
      MemoryEventInsert.minimal(
        deviceId: DeviceId(1),
        streamId: 'test',
        kind: 'event-$i',
      ),
    );
  }
}
