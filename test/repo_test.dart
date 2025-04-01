import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:notes_app_v0/common.dart';

// run only non-flutter tests with
// flutter test --exclude-tags=flutter

void main() {
  group('Repo Granular Reactivity', () {
    late Repo repo;

    setUp(() {
      repo = Repo.empty();
    });

    tearDown(() {
      repo.dispose();
    });

    test('Individual note should emit changes when updated', () async {
      final order = repo.order;

      final noteId = Id('1');
      final timestamp = DateTime.fromMillisecondsSinceEpoch(1000);

      expectLater(order.changes, emits(anything));
      await repo.processEvent(NoteCreated(noteId), timestamp);

      final noteData = await repo.getNote(noteId);

      expectLater(noteData!.changes, emits(anything));
      await repo.processEvent(
        NoteContentUpdated(noteId, 'Updated content'),
        timestamp,
      );

      expect(order.items, equals([noteId]));
      expect(noteData.content, equals('Updated content'));

      // now check from the repo perspective
      expect(repo.order.items, equals([noteId]));
      expect((await repo.getNote(noteId))!.content, equals('Updated content'));
    });

    test('Note ordering', () async {
      // Arrange
      final noteId1 = Id('1');
      final noteId2 = Id('2');
      await repo.processEvent(NoteCreated(noteId1), DateTime.now());
      await repo.processEvent(NoteCreated(noteId2), DateTime.now());

      // notes are ordered in "reverse order"
      final order = repo.order;
      expect(order.items, equals([noteId2, noteId1]));

      expectLater(order.changes, emits(anything));
      await repo.processEvent(
        NoteMoved(noteId2, 1),
        DateTime.now(),
      ); // moved to end (aka one)

      expect(order.items, equals([noteId1, noteId2]));
    });

    test(
      'Updates to one note should not trigger events for other notes',
      () async {
        // Arrange
        final noteId1 = Id('1');
        final noteId2 = Id('2');

        await repo.processEvent(NoteCreated(noteId1), DateTime.now());
        await repo.processEvent(NoteCreated(noteId2), DateTime.now());

        final _ = await repo.getNote(noteId1);
        final note2 = await repo.getNote(noteId2);

        // Set up a counter to track emissions
        var note2ChangeCount = 0;
        final subscription = note2!.changes.listen((_) {
          note2ChangeCount++;
        });

        // Act - only update note1
        await repo.processEvent(
          NoteContentUpdated(noteId1, 'Updated content'),
          DateTime.now(),
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
