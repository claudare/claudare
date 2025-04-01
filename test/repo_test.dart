import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';

// run only non-flutter tests with
// flutter test --exclude-tags=flutter

// this needs a lot more testing, especially when the AppStorage is used
void main() {
  group('Repo Granular Reactivity', () {
    late Repo repo;
    final eventId1 = EventId(Timestamp(1000), DeviceId(0));
    final eventId2 = EventId(Timestamp(1001), DeviceId(0));
    final eventId3 = EventId(Timestamp(1002), DeviceId(0));

    final noteId1 = GenericId(
      'note',
      Timestamp(1000),
      Counter16(0),
      DeviceId(0),
    );
    final noteId2 = GenericId(
      'note',
      Timestamp(1001),
      Counter16(1),
      DeviceId(0),
    );

    setUp(() {
      repo = Repo.empty();
    });

    tearDown(() {
      repo.dispose();
    });

    test('Can init from events', () async {
      await repo.loadFromEvents([
        (eventId1, NoteCreated(noteId1)),
        (eventId2, NoteCreated(noteId2)),
      ]);

      expect(repo.order.items.length, equals(2));
    });

    test('Individual note should emit changes when updated', () async {
      final order = repo.order;

      expectLater(order.changes, emits(anything));
      await repo.processEvent(eventId1, NoteCreated(noteId1));

      final noteData = await repo.getNote(noteId1);

      expectLater(noteData!.changes, emits(anything));
      await repo.processEvent(
        eventId2,
        NoteContentUpdated(noteId1, 'Updated content'),
      );

      expect(order.items, equals([noteId1]));
      expect(noteData.content, equals('Updated content'));

      // now check from the repo perspective
      expect(repo.order.items, equals([noteId1]));
      expect((await repo.getNote(noteId1))!.content, equals('Updated content'));
    });

    test('Note ordering', () async {
      await repo.processEvent(eventId1, NoteCreated(noteId1));
      await repo.processEvent(eventId2, NoteCreated(noteId2));

      // notes are ordered in "reverse order"
      final order = repo.order;
      expect(order.items, equals([noteId2, noteId1]));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        eventId3,
        NoteMoved(noteId2, 1),
      ); // moved to end (aka one)

      expect(order.items, equals([noteId1, noteId2]));
    });

    test(
      'Updates to one note should not trigger events for other notes',
      () async {
        await repo.processEvent(eventId1, NoteCreated(noteId1));
        await repo.processEvent(eventId2, NoteCreated(noteId2));

        final _ = await repo.getNote(noteId1);
        final note2 = await repo.getNote(noteId2);

        // Set up a counter to track emissions
        var note2ChangeCount = 0;
        final subscription = note2!.changes.listen((_) {
          note2ChangeCount++;
        });

        // Act - only update note1
        await repo.processEvent(
          eventId3,
          NoteContentUpdated(noteId1, 'Updated content'),
        );

        // Give time for any potential emissions to occur
        await Future.delayed(Duration(milliseconds: 50));

        // Clean up
        await subscription.cancel();

        // Assert
        expect(
          note2ChangeCount,
          0,
          reason: 'Note2 should not receive changes when Note1 is updated',
        );
      },
    );
  });
}
