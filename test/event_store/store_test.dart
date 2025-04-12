import 'package:test/test.dart';
import 'dart:convert';

import 'package:core/database.dart';
import 'package:core/event_store.dart';
import 'package:core/core.dart';

void main() {
  group('EventStore', () {
    final deviceA = DeviceId(0);
    final deviceB = DeviceId(1);

    late EventStore eventStore;

    setUp(() async {
      eventStore = EventStore.temporary();
      await eventStore.init();

      final firstEventId = EventId(Timestamp(1000), 1, deviceA);
      final secondEventId = EventId(Timestamp(2000), 1, deviceB);

      final eventData1 = utf8.encode('first');
      final eventData2 = utf8.encode('second');

      // Insert events
      await eventStore.storeEvent(StoredEvent(firstEventId, eventData1));
      await eventStore.storeEvent(StoredEvent(secondEventId, eventData2));
    });

    tearDown(() async {
      await eventStore.deinit();
      await databaseDELETE(eventStore);
    });

    test('query events', () async {
      // Query events
      final cursor = EventVectorClock.fromEventIds([
        EventId(Timestamp.zero(), 0, deviceA),
        EventId(Timestamp.zero(), 0, deviceB),
      ]);
      final eventStream = eventStore.getEvents(cursor, 2);
      final events = await eventStream.toList();

      expect(events.length, equals(2));
      expect(events[0].id, EventId(Timestamp(1000), 1, deviceA));
      expect(events[0].bytes, equals(utf8.encode('first')));
      expect(events[1].id, EventId(Timestamp(2000), 1, deviceB));
      expect(events[1].bytes, equals(utf8.encode('second')));
    });

    test('insert events', () async {
      final cursor = eventStore.vectorClock.clone();
      final eventId = EventId(Timestamp(3000), 2, deviceA);

      await eventStore.storeEvent(StoredEvent(eventId, utf8.encode('third')));

      // Check vector clock update
      final events = await eventStore.getEvents(cursor, 99).toList();
      expect(events.length, equals(1));
      expect(events[0].id, EventId(Timestamp(3000), 2, deviceA));
      expect(events[0].bytes, equals(utf8.encode('third')));
    });

    test('vector clock updates with new events', () async {
      final eventId = EventId(Timestamp(3000), 2, deviceA);

      await eventStore.storeEvent(StoredEvent(eventId, utf8.encode('third')));

      // Check vector clock update
      expect(eventStore.vectorClock[deviceA], equals(eventId));
    });
  });
}
