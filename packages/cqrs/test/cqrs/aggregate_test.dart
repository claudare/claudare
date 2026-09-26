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

      expect(state, ['a:account/one:opened', 'a:account/two:deposit']);
    });

    test('passes an explicit actor to the aggregate', () {
      final state =
          AggregateTester(_RecordingAggregate())
              .withEvent(
                'account/one',
                'opened',
                actor: 'b',
                occuredAt: occurredAt,
              )
              .run();

      expect(state, ['b:account/one:opened']);
    });

    test('checks canApply before applying an event', () {
      final state =
          (AggregateTester(_RecordingAggregate())
                ..withEvent('account/one', 'skip', occuredAt: occurredAt)
                ..withEvent('account/skip', 'kept', occuredAt: occurredAt))
              .run();

      expect(state, ['a:account/skip:kept']);
    });
  });
}

final class _RecordingAggregate implements Aggregate<String, List<String>> {
  @override
  Snapshotter<List<String>>? get snapshotter => null;

  @override
  int get version => 1;

  @override
  StreamRoute get streamRoute => StreamRouteWildcard('account/*');

  @override
  List<String> initialState() => [];

  @override
  bool canApply(EventEnvelope<String> envelope) => envelope.event != 'skip';

  @override
  void apply(List<String> state, EventEnvelope<String> envelope) {
    state.add('${envelope.actor}:${envelope.streamPath}:${envelope.event}');
  }
}
