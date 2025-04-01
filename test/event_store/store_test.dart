import 'package:core/src/database.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:test/test.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/store.dart';

void main() {
  group('EventStore', () {
    final deviceA = DeviceId(0);
    final deviceB = DeviceId(1);
    late EventStore eventStore;

    setUp(() async {
      eventStore = EventStore.temporary();
      await eventStore.init();

      final firstEventId = EventId(Timestamp(1000), deviceA);
      final secondEventId = EventId(Timestamp(2000), deviceB);

      final eventData1 = 'first';
      final eventData2 = 'second';

      // Insert events
      await eventStore.storeEvent(StoredEvent(firstEventId, eventData1));
      await eventStore.storeEvent(StoredEvent(secondEventId, eventData2));
    });

    tearDown(() async {
      await eventStore.deinit();
      await databaseDELETE(eventStore);
    });

    test('insert and query events', () async {
      // Query events
      final cursor = EventVectorClockRange.fromStart(eventStore.vectorClock);
      final eventStream = eventStore.getEvents(cursor, 2);

      final events = await eventStream.toList();

      expect(events.length, equals(2));
      expect(events[0].id, EventId(Timestamp(1000), deviceA));
      expect(events[0].data, 'first');
      expect(events[1].id, EventId(Timestamp(2000), deviceB));
      expect(events[1].data, 'second');
    });

    test('vector clock updates with new events', () async {
      final eventId = EventId(Timestamp(3000), deviceA);

      await eventStore.storeEvent(StoredEvent(eventId, 'third'));

      // Check vector clock update
      expect(eventStore.vectorClock[deviceA], equals(eventId));
    });

    test('vector clock updates with new events', () async {
      final eventId = EventId(
        Timestamp(2000),
        deviceA,
      ); // device A should be returned second

      await eventStore.storeEvent(StoredEvent(eventId, 'third'));

      // construct first event range
      final range = EventVectorClockRange.fromStart(eventStore.vectorClock);

      final [first] = await eventStore.getEvents(range, 1).toList();
      range.advanceById(first.id);
      expect(first.id, equals(EventId(Timestamp(1000), deviceA)));

      final [second] = await eventStore.getEvents(range, 1).toList();
      range.advanceById(second.id);
      expect(second.id, equals(EventId(Timestamp(2000), deviceA)));

      final [third] = await eventStore.getEvents(range, 1).toList();
      range.advanceById(third.id);
      expect(third.id, equals(EventId(Timestamp(2000), deviceB)));

      // the cursor should never be empty!
      expect(() => eventStore.getEvents(range, 1).toList(), throwsException);
    });
  });
}
