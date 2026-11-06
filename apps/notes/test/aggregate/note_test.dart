import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes_app/src/aggregate/note.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  final editedAt = DateTime.utc(2026, 1, 2);
  final laterAt = DateTime.utc(2026, 1, 3);

  test('starts absent and ignores another note stream', () {
    final state = AggregateTester(noteAggregate('one'))
        .withEvent('note/two', const NoteCreated(), occuredAt: createdAt)
        .run();

    expect(state.exists, isFalse);
    expect(state.noteId, 'one');
  });

  test('replays creation, title, and content with timestamps', () {
    final state = AggregateTester(noteAggregate('one'))
        .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
        .withEvent(
          'note/one',
          const NoteTitleUpdated(newTitle: 'Title'),
          occuredAt: editedAt,
        )
        .withEvent(
          'note/one',
          NoteContentUpdated(change: CrdtTextTestUtils.singleChange('Text')),
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
    final state = AggregateTester(noteAggregate('one'))
        .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
        .withEvent(
          'note/one',
          const NoteTitleUpdated(newTitle: 'Newer'),
          occuredAt: laterAt,
        )
        .withEvent(
          'note/one',
          const NoteTitleUpdated(newTitle: 'Older'),
          occuredAt: editedAt,
        )
        .run();

    expect(state.title, 'Newer');
    expect(state.updatedAt, editedAt);
  });

  test('uses the greater actor when title timestamps tie', () {
    final state = AggregateTester(noteAggregate('one'))
        .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
        .withEvent(
          'note/one',
          const NoteTitleUpdated(newTitle: 'First'),
          actor: 'b',
          occuredAt: editedAt,
        )
        .withEvent(
          'note/one',
          const NoteTitleUpdated(newTitle: 'Second'),
          actor: 'a',
          occuredAt: editedAt,
        )
        .run();

    expect(state.title, 'First');
  });

  test('trash and restore change only trash state', () {
    final tester = AggregateTester(noteAggregate('one'))
        .withEvent('note/one', const NoteCreated(), occuredAt: createdAt)
        .withEvent('note/one', const NoteTrashed(), occuredAt: editedAt);

    final trashed = tester.run();
    expect(trashed.isTrashed, isTrue);
    expect(trashed.trashedAt, editedAt);
    expect(trashed.updatedAt, createdAt);

    final restored = tester
        .withEvent('note/one', const NoteRestored(), occuredAt: laterAt)
        .run();
    expect(restored.isTrashed, isFalse);
    expect(restored.trashedAt, isNull);
    expect(restored.updatedAt, createdAt);
  });
}
