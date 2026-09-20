import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

  group('AggregateTester', () {
    test('starts with fresh state on every run', () {
      final tester = AggregateTester(_RecordingAggregate());

      final first = tester.run();
      first.add('changed');

      expect(tester.run(), isEmpty);
    });

    test('applies matching events in order with their envelopes', () {
      final state =
          (AggregateTester(_RecordingAggregate())
                ..withEvent('account/one', 'opened', occuredAt: occurredAt)
                ..withEvent('other/two', 'ignored', occuredAt: occurredAt)
                ..withEvent('account/two', 'deposit', occuredAt: occurredAt))
              .run();

      expect(state, ['0:account/one:one:opened', '2:account/two:two:deposit']);
    });

    test('checks canApply before applying an event', () {
      final state =
          (AggregateTester(_RecordingAggregate())
                ..withEvent('account/skip', 'ignored', occuredAt: occurredAt)
                ..withEvent('account/one', 'kept', occuredAt: occurredAt))
              .run();

      expect(state, ['1:account/one:one:kept']);
    });
  });
}

final class _RecordingAggregate
    implements Aggregate<String, String, List<String>> {
  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('account/*');

  @override
  List<String> initialState() => [];

  @override
  bool canApply(EventEnvelope<String, String> envelope) =>
      envelope.streamParams != 'skip';

  @override
  void apply(List<String> state, EventEnvelope<String, String> envelope) {
    state.add(
      '${envelope.localSequence}:${envelope.streamPath}:${envelope.streamParams}:${envelope.event}',
    );
  }
}
