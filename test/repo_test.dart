import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';

// run only non-flutter tests with
// flutter test --exclude-tags=flutter

// TODO: all timestamps can be omitted from this testing
// as they are irrelevant to functionality of the app
// the tests should work with automatic timestamp generation
// timestamps should only be used when conflicts are tested for.

void main() {
  group('Repo Granular Reactivity', () {
    late Repo repo;

    setUp(() {
      repo = Repo.empty();
    });

    tearDown(() {
      repo.dispose();
    });

    test('Can init from events', () async {
      await repo.loadFromEvents([
        (
          EventId(Timestamp(1000), DeviceId(0)),
          NoteCreated(repo.newGenericId('note', timestamp: Timestamp(1000))),
        ),
        (
          EventId(Timestamp(1001), DeviceId(0)),
          NoteCreated(repo.newGenericId('note', timestamp: Timestamp(1001))),
        ),
      ]);

      expect(repo.order.items.length, equals(2));
    });

    test('Individual note should emit changes when updated', () async {
      final order = repo.order;

      final noteId = repo.newGenericId('note', timestamp: Timestamp(1000));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        repo.newEventId(timestamp: Timestamp(1000)),
        NoteCreated(noteId),
      );

      final noteData = await repo.getNote(noteId);

      expectLater(noteData!.changes, emits(anything));
      await repo.processEvent(
        repo.newEventId(timestamp: Timestamp(1000)),
        NoteContentUpdated(noteId, 'Updated content'),
      );

      expect(order.items, equals([noteId]));
      expect(noteData.content, equals('Updated content'));

      // now check from the repo perspective
      expect(repo.order.items, equals([noteId]));
      expect((await repo.getNote(noteId))!.content, equals('Updated content'));
    });

    test('Note ordering', () async {
      // Arrange
      final noteId1 = repo.newGenericId('note', timestamp: Timestamp(1000));
      final noteId2 = repo.newGenericId('note', timestamp: Timestamp(1000));
      await repo.processEvent(repo.newEventId(), NoteCreated(noteId1));
      await repo.processEvent(repo.newEventId(), NoteCreated(noteId2));

      // notes are ordered in "reverse order"
      final order = repo.order;
      expect(order.items, equals([noteId2, noteId1]));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        repo.newEventId(),
        NoteMoved(noteId2, 1),
      ); // moved to end (aka one)

      expect(order.items, equals([noteId1, noteId2]));
    });

    test(
      'Updates to one note should not trigger events for other notes',
      () async {
        final noteId1 = repo.newGenericId('note', timestamp: Timestamp(1000));
        final noteId2 = repo.newGenericId('note', timestamp: Timestamp(1000));

        await repo.processEvent(
          repo.newEventId(timestamp: Timestamp(1000)),
          NoteCreated(noteId1),
        );
        await repo.processEvent(
          repo.newEventId(timestamp: Timestamp(1000)),
          NoteCreated(noteId2),
        );

        final _ = await repo.getNote(noteId1);
        final note2 = await repo.getNote(noteId2);

        // Set up a counter to track emissions
        var note2ChangeCount = 0;
        final subscription = note2!.changes.listen((_) {
          note2ChangeCount++;
        });

        // Act - only update note1
        await repo.processEvent(
          repo.newEventId(timestamp: Timestamp(2000)),
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
