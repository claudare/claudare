import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  final occuredAt = DateTime.utc(2026);

  test('AggregateTester retains state and applies each event once', () {
    final aggregate = _recordingAggregate();
    final tester = AggregateTester(aggregate);
    final first = tester.run();
    tester.withEvent('account/one', 'opened', occuredAt: occuredAt);
    final second = tester.run();

    expect(second, same(first));
    expect(second, same(aggregate.state));
    expect(second.values, ['a:account/one:opened']);
    expect(tester.run().values, ['a:account/one:opened']);
  });

  test('AggregateTester applies matching events in order', () {
    final state =
        (AggregateTester(_recordingAggregate())
              ..withEvent('account/one', 'opened', occuredAt: occuredAt)
              ..withEvent('other/two', 'ignored', occuredAt: occuredAt)
              ..withEvent('account/two', 'deposit', occuredAt: occuredAt))
            .run();

    expect(state.values, ['a:account/one:opened', 'a:account/two:deposit']);
  });

  test('AggregateTester passes an explicit actor', () {
    final state = AggregateTester(_recordingAggregate())
        .withEvent('account/one', 'opened', actor: 'b', occuredAt: occuredAt)
        .run();

    expect(state.values, ['b:account/one:opened']);
  });
}

final class _RecordingState implements AggregateState<String> {
  final values = <String>[];

  @override
  void apply(EventEnvelope<String> envelope) {
    values.add('${envelope.actor}:${envelope.streamPath}:${envelope.event}');
  }
}

Aggregate<String, _RecordingState> _recordingAggregate() => Aggregate(
  name: 'Recording',
  filter: const PatternFilter.startsWith('account/'),
  state: _RecordingState(),
);
