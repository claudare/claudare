import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';

// run only non-flutter tests with
// flutter test --exclude-tags=flutter

void main() {
  group('Repo Granular Reactivity', () {
    late Repo repo;

    setUp(() {
      repo = Repo.empty(DeviceId(0));
    });

    tearDown(() {
      repo.dispose();
    });

    test('Individual note should emit changes when updated', () async {
      final order = repo.order;

      final noteId = repo.genericIdGen.next('note', Timestamp(1000));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        repo.eventIdGen.next(Timestamp(1000)),
        NoteCreated(noteId),
      );

      final noteData = await repo.getNote(noteId);

      expectLater(noteData!.changes, emits(anything));
      await repo.processEvent(
        repo.eventIdGen.next(Timestamp(1000)),
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
      final noteId1 = repo.genericIdGen.next('note', Timestamp(1000));
      final noteId2 = repo.genericIdGen.next('note', Timestamp(1000));
      await repo.processEvent(
        repo.eventIdGen.next(Timestamp(2000)),
        NoteCreated(noteId1),
      );
      await repo.processEvent(
        repo.eventIdGen.next(Timestamp(2000)),
        NoteCreated(noteId2),
      );

      // notes are ordered in "reverse order"
      final order = repo.order;
      expect(order.items, equals([noteId2, noteId1]));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        repo.eventIdGen.next(Timestamp(3000)),
        NoteMoved(noteId2, 1),
      ); // moved to end (aka one)

      expect(order.items, equals([noteId1, noteId2]));
    });

    test(
      'Updates to one note should not trigger events for other notes',
      () async {
        final noteId1 = repo.genericIdGen.next('note', Timestamp(1000));
        final noteId2 = repo.genericIdGen.next('note', Timestamp(1000));

        await repo.processEvent(
          repo.eventIdGen.next(Timestamp(1000)),
          NoteCreated(noteId1),
        );
        await repo.processEvent(
          repo.eventIdGen.next(Timestamp(1000)),
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
          repo.eventIdGen.next(Timestamp(2000)),
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
