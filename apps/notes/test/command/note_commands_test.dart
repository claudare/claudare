import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/restore_note.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  CommandTester newTester() =>
      CommandTester(timeProvider: FakeTimeProviderStatic.zero())
        ..registerEvent(const NoteContentUpdatedCodec())
        ..registerEvent(const NoteCreatedCodec())
        ..registerEvent(const NoteRestoredCodec())
        ..registerEvent(const NoteTitleUpdatedCodec())
        ..registerEvent(const NoteTrashedCodec());

  test('create writes a note creation event', () async {
    final tester = newTester();

    await tester.run(const CreateNote(), const CreateNoteInput(noteId: 'one'));

    final events = await tester.getWrittenEvents<NoteEvent, String>(
      noteStreamRoute,
      'one',
    );
    expect(events, hasLength(1));
    expect(events.single, isA<NoteCreated>());
  });

  test('create rejects an existing note', () async {
    final tester =
        newTester()..withEvent(noteStreamRoute, 'one', const NoteCreated());

    await expectLater(
      tester.run(const CreateNote(), const CreateNoteInput(noteId: 'one')),
      throwsA(isA<StreamAlreadyExistsException>()),
    );
  });

  test('title update writes the supplied value', () async {
    final tester =
        newTester()..withEvent(noteStreamRoute, 'one', const NoteCreated());

    await tester.run(
      const UpdateNoteTitle(),
      const UpdateNoteTitleInput(noteId: 'one', fullValue: 'Title'),
    );

    final events = await tester.getWrittenEvents<NoteEvent, String>(
      noteStreamRoute,
      'one',
    );
    expect(events, hasLength(1));
    expect(events.single, isA<NoteTitleUpdated>());
    expect((events.single as NoteTitleUpdated).newTitle, 'Title');
  });

  test('content update writes the supplied value', () async {
    final tester =
        newTester()..withEvent(noteStreamRoute, 'one', const NoteCreated());

    await tester.run(
      const UpdateNoteContent(),
      const UpdateNoteContentInput(noteId: 'one', overrideContent: 'Body'),
    );

    final events = await tester.getWrittenEvents<NoteEvent, String>(
      noteStreamRoute,
      'one',
    );
    expect(events, hasLength(1));
    expect(events.single, isA<NoteContentUpdated>());
    expect((events.single as NoteContentUpdated).newContent, 'Body');
  });

  test('title update rejects a missing note', () async {
    await expectLater(
      newTester().run(
        const UpdateNoteTitle(),
        const UpdateNoteTitleInput(noteId: 'one', fullValue: 'Title'),
      ),
      throwsA(isA<StreamNotFoundException>()),
    );
  });

  test('content update rejects a missing note', () async {
    await expectLater(
      newTester().run(
        const UpdateNoteContent(),
        const UpdateNoteContentInput(noteId: 'one', overrideContent: 'Body'),
      ),
      throwsA(isA<StreamNotFoundException>()),
    );
  });

  test('trash writes an event for an active note', () async {
    final tester =
        newTester()..withEvent(noteStreamRoute, 'one', const NoteCreated());

    await tester.run(const TrashNote(), const TrashNoteInput(noteId: 'one'));

    final events = await tester.getWrittenEvents<NoteEvent, String>(
      noteStreamRoute,
      'one',
    );
    expect(events, hasLength(1));
    expect(events.single, isA<NoteTrashed>());
  });

  test('trash rejects a note that is already trashed', () async {
    final tester =
        newTester()
          ..withEvent(noteStreamRoute, 'one', const NoteCreated())
          ..withEvent(noteStreamRoute, 'one', const NoteTrashed());

    await expectLater(
      tester.run(const TrashNote(), const TrashNoteInput(noteId: 'one')),
      throwsA(isA<CommandException>()),
    );
  });

  test('trash rejects a missing note', () async {
    await expectLater(
      newTester().run(const TrashNote(), const TrashNoteInput(noteId: 'one')),
      throwsA(isA<CommandException>()),
    );
  });

  test('restore writes an event for a trashed note', () async {
    final tester =
        newTester()
          ..withEvent(noteStreamRoute, 'one', const NoteCreated())
          ..withEvent(noteStreamRoute, 'one', const NoteTrashed());

    await tester.run(
      const RestoreNote(),
      const RestoreNoteInput(noteId: 'one'),
    );

    final events = await tester.getWrittenEvents<NoteEvent, String>(
      noteStreamRoute,
      'one',
    );
    expect(events, hasLength(1));
    expect(events.single, isA<NoteRestored>());
  });

  test('restore rejects a note that is not trashed', () async {
    final tester =
        newTester()..withEvent(noteStreamRoute, 'one', const NoteCreated());

    await expectLater(
      tester.run(const RestoreNote(), const RestoreNoteInput(noteId: 'one')),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          'Exception: note was not trashed',
        ),
      ),
    );
  });
}
