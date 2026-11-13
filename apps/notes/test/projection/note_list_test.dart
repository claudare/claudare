import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes_app/src/projection/note_list_projection.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  final firstAt = DateTime.utc(2026, 1, 1);
  final secondAt = DateTime.utc(2026, 1, 2);
  final editedAt = DateTime.utc(2026, 1, 3);
  final trashedAt = DateTime.utc(2026, 1, 4);

  Future<NoteListModel> replayNotes() => ProjectionTester(NoteListProjection())
      .withEvent('other/ignored', const NoteCreated(), occuredAt: firstAt)
      .withEvent('note/one', const NoteCreated(), occuredAt: firstAt)
      .withEvent('note/two', const NoteCreated(), occuredAt: secondAt)
      .withEvent(
        'note/one',
        const NoteTitleUpdated(newTitle: 'One'),
        occuredAt: editedAt,
      )
      .withEvent('note/two', const NoteTrashed(), occuredAt: trashedAt)
      .run();

  test('collects note streams and counts active notes', () async {
    final state = await replayNotes();

    expect(
      state.toSortedList(category: NoteCategory.all).map((n) => n.noteId),
      containsAll(['one', 'two']),
    );
    expect(state.toSortedList(category: NoteCategory.all), hasLength(2));
    expect(state.toSortedList().single.title, 'One');
    expect(
      state.toSortedList(category: NoteCategory.trashed).single.trashedAt,
      trashedAt,
    );
    expect(state.activeCount, 1);
  });

  test('keys notes from the stream path', () async {
    final state = await ProjectionTester(NoteListProjection())
        .withEvent('note/one', const NoteCreated(), occuredAt: firstAt)
        .run();

    expect(state.toSortedList().map((n) => n.noteId), ['one']);
    expect(state.toSortedList().single.noteId, 'one');
  });

  test('filters active, trashed, and all notes', () async {
    final state = await replayNotes();

    expect(state.toSortedList().map((note) => note.noteId), ['one']);
    expect(
      state
          .toSortedList(category: NoteCategory.trashed)
          .map((note) => note.noteId),
      ['two'],
    );
    expect(
      state.toSortedList(category: NoteCategory.all).map((note) => note.noteId),
      ['two', 'one'],
    );
  });

  test('sorts chronologically by creation and update time', () async {
    final state = await replayNotes();

    expect(
      state
          .toSortedList(
            category: NoteCategory.all,
            order: NoteSortOrder.createdAtAscending,
          )
          .map((note) => note.noteId),
      ['one', 'two'],
    );
    expect(
      state
          .toSortedList(
            category: NoteCategory.all,
            order: NoteSortOrder.updatedAtDescending,
          )
          .map((note) => note.noteId),
      ['one', 'two'],
    );
    expect(
      state
          .toSortedList(
            category: NoteCategory.all,
            order: NoteSortOrder.updatedAtAscending,
          )
          .map((note) => note.noteId),
      ['two', 'one'],
    );
  });

  test('restoring a note returns it to the active list', () async {
    final state = await ProjectionTester(NoteListProjection())
        .withEvent('note/one', const NoteCreated(), occuredAt: firstAt)
        .withEvent('note/one', const NoteTrashed(), occuredAt: secondAt)
        .withEvent('note/one', const NoteRestored(), occuredAt: editedAt)
        .run();

    expect(state.activeCount, 1);
    expect(state.toSortedList().single.noteId, 'one');
    expect(state.toSortedList(category: NoteCategory.trashed), isEmpty);
  });
}
