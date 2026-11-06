import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes_app/src/aggregate/note_list.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  final firstAt = DateTime.utc(2026, 1, 1);
  final secondAt = DateTime.utc(2026, 1, 2);
  final editedAt = DateTime.utc(2026, 1, 3);
  final trashedAt = DateTime.utc(2026, 1, 4);

  NoteListState replayNotes() => AggregateTester(noteListAggregate())
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

  test('collects note streams and counts active notes', () {
    final state = replayNotes();

    expect(state.notes.keys, containsAll(['one', 'two']));
    expect(state.notes, hasLength(2));
    expect(state.notes['one']!.title, 'One');
    expect(state.notes['two']!.trashedAt, trashedAt);
    expect(state.activeCount, 1);
  });

  test('keys notes from the stream path', () {
    final state = AggregateTester(noteListAggregate())
        .withEvent('note/one', const NoteCreated(), occuredAt: firstAt)
        .run();

    expect(state.notes.keys, ['one']);
    expect(state.notes['one']!.noteId, 'one');
  });

  test('filters active, trashed, and all notes', () {
    final state = replayNotes();

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

  test('sorts chronologically by creation and update time', () {
    final state = replayNotes();

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

  test('restoring a note returns it to the active list', () {
    final state = AggregateTester(noteListAggregate())
        .withEvent('note/one', const NoteCreated(), occuredAt: firstAt)
        .withEvent('note/one', const NoteTrashed(), occuredAt: secondAt)
        .withEvent('note/one', const NoteRestored(), occuredAt: editedAt)
        .run();

    expect(state.activeCount, 1);
    expect(state.toSortedList().single.noteId, 'one');
    expect(state.toSortedList(category: NoteCategory.trashed), isEmpty);
  });
}
