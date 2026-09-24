import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes/aggregate/note.dart';
import 'package:notes/event/note.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  final editedAt = DateTime.utc(2026, 1, 2);
  final laterAt = DateTime.utc(2026, 1, 3);

  test('starts absent and ignores another note stream', () {
    final state =
        AggregateTester(NoteAggregate('one'))
            .withEvent('note/two', const NoteCreated(), occuredAt: createdAt)
            .run();

    expect(state.exists, isFalse);
    expect(state.noteId, 'one');
  });

  test('replays creation, title, and content with timestamps', () {
    final state =
        AggregateTester(NoteAggregate('one'))
            .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
            .withEvent(
              'note/one',
              const NoteTitleUpdated(noteId: 'one', newTitle: 'Title'),
              occuredAt: editedAt,
            )
            .withEvent(
              'note/one',
              const NoteContentUpdated(noteId: 'one', newContent: 'Text'),
              occuredAt: laterAt,
            )
            .run();

    expect(state.exists, isTrue);
    expect(state.title, 'Title');
    expect(state.content, 'Text');
    expect(state.createdAt, createdAt);
    expect(state.updatedAt, laterAt);
    expect(state.isTrashed, isFalse);
  });

  test('keeps the title with the latest timestamp', () {
    final state =
        AggregateTester(NoteAggregate('one'))
            .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
            .withEvent(
              'note/one',
              const NoteTitleUpdated(noteId: 'one', newTitle: 'Newer'),
              occuredAt: laterAt,
            )
            .withEvent(
              'note/one',
              const NoteTitleUpdated(noteId: 'one', newTitle: 'Older'),
              occuredAt: editedAt,
            )
            .run();

    expect(state.title, 'Newer');
    expect(state.updatedAt, editedAt);
  });

  test('uses the later event when title timestamps tie', () {
    final state =
        AggregateTester(NoteAggregate('one'))
            .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
            .withEvent(
              'note/one',
              const NoteTitleUpdated(noteId: 'one', newTitle: 'First'),
              occuredAt: editedAt,
            )
            .withEvent(
              'note/one',
              const NoteTitleUpdated(noteId: 'one', newTitle: 'Second'),
              occuredAt: editedAt,
            )
            .run();

    expect(state.title, 'Second');
  });

  test('trash and restore change only trash state', () {
    final tester = AggregateTester(NoteAggregate('one'))
        .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
        .withEvent('note/one', const NoteTrashed(), occuredAt: editedAt);

    final trashed = tester.run();
    expect(trashed.isTrashed, isTrue);
    expect(trashed.trashedAt, editedAt);
    expect(trashed.updatedAt, createdAt);

    final restored =
        tester
            .withEvent('note/one', const NoteRestored(), occuredAt: laterAt)
            .run();
    expect(restored.isTrashed, isFalse);
    expect(restored.trashedAt, isNull);
    expect(restored.updatedAt, createdAt);
  });
}
