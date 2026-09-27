import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes/aggregate/statistics.dart';
import 'package:notes/event/note.dart';
import 'package:test/test.dart';

void main() {
  test('statistics counts events and active notes', () {
    final state = AggregateTester(statisticsAggregate())
        .withEvent(
          'note/one',
          const NoteCreated(noteId: 'one'),
          occuredAt: DateTime.utc(2026, 1, 1),
        )
        .withEvent(
          'note/two',
          const NoteCreated(noteId: 'two'),
          occuredAt: DateTime.utc(2026, 1, 2),
        )
        .run();

    expect(state.eventCount, 2);
    expect(state.activeCount, 2);
  });

  test('later replayed change wins when timestamps tie', () {
    final time = DateTime.utc(2026, 1, 1);
    final state = AggregateTester(statisticsAggregate())
        .withEvent(
          'note/one',
          const NoteCreated(noteId: 'one'),
          occuredAt: time,
        )
        .withEvent(
          'note/one',
          const NoteTrashed(noteId: 'one'),
          occuredAt: time,
        )
        .withEvent(
          'note/one',
          const NoteRestored(noteId: 'one'),
          occuredAt: time,
        )
        .run();

    expect(state.eventCount, 3);
    expect(state.activeCount, 1);
  });

  test('older trash does not override a later restore', () {
    final state = AggregateTester(statisticsAggregate())
        .withEvent(
          'note/one',
          const NoteCreated(noteId: 'one'),
          occuredAt: DateTime.utc(2026, 1, 1),
        )
        .withEvent(
          'note/one',
          const NoteRestored(noteId: 'one'),
          occuredAt: DateTime.utc(2026, 1, 3),
        )
        .withEvent(
          'note/one',
          const NoteTrashed(noteId: 'one'),
          occuredAt: DateTime.utc(2026, 1, 2),
        )
        .run();

    expect(state.activeCount, 1);
  });
}
