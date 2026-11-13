import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes_app/src/projection/statistics_projection.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

void main() {
  test('statistics counts active notes', () async {
    final state = await ProjectionTester(StatisticsProjection())
        .withEvent(
          'note/one',
          const NoteCreated(),
          occuredAt: DateTime.utc(2026, 1, 1),
        )
        .withEvent(
          'note/two',
          const NoteCreated(),
          occuredAt: DateTime.utc(2026, 1, 2),
        )
        .run();

    expect(state.activeCount, 2);
  });

  test('later replayed change wins when timestamps tie', () async {
    final time = DateTime.utc(2026, 1, 1);
    final state = await ProjectionTester(StatisticsProjection())
        .withEvent('note/one', const NoteCreated(), occuredAt: time)
        .withEvent('note/one', const NoteTrashed(), occuredAt: time)
        .withEvent('note/one', const NoteRestored(), occuredAt: time)
        .run();

    expect(state.activeCount, 1);
  });

  test('older trash does not override a later restore', () async {
    final state = await ProjectionTester(StatisticsProjection())
        .withEvent(
          'note/one',
          const NoteCreated(),
          occuredAt: DateTime.utc(2026, 1, 1),
        )
        .withEvent(
          'note/one',
          const NoteRestored(),
          occuredAt: DateTime.utc(2026, 1, 3),
        )
        .withEvent(
          'note/one',
          const NoteTrashed(),
          occuredAt: DateTime.utc(2026, 1, 2),
        )
        .run();

    expect(state.activeCount, 1);
  });
}
