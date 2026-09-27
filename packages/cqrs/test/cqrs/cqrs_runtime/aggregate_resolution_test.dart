import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

final _timestamp = DateTime.utc(2026);

void main() {
  late EventStore eventStore;
  late CqrsRuntime runtime;

  setUp(() {
    eventStore = MemoryEventStore(eventFetchPageSize: 1);
    runtime = CqrsRuntime(
      actor: 'test-actor',
      eventStore: eventStore,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
      notificationBus: MemoryNotificationBus(),
    );
    runtime.eventRegistry
      ..add(const _TestEventCodec())
      ..freeze();
  });

  test('resolves matching events and resumes across filtered pages', () async {
    final aggregate = _envelopeAggregate('account/one');
    expect((await runtime.resolve(aggregate)).state.events, isEmpty);
    expect(aggregate.sequence, isNull);

    await _appendAccountEvents(eventStore);
    expect(identical(await runtime.resolve(aggregate), aggregate), isTrue);
    expect(aggregate.state.events.map((v) => v.event.value), [
      'opened',
      'deposit',
    ]);
    expect(aggregate.sequence, 3);

    await runtime.resolve(aggregate);
    expect(aggregate.state.events, hasLength(2));
    expect(aggregate.sequence, 3);
  });

  test('fresh aggregates have independent state', () async {
    await _appendAccountEvents(eventStore);
    final first = await runtime.resolve(_envelopeAggregate('account/one'));
    final second = await runtime.resolve(_envelopeAggregate('account/one'));

    expect(first.state.events, hasLength(2));
    expect(second.state.events, hasLength(2));
    expect(identical(first.state, second.state), isFalse);
  });

  test('uses log paths, actors, and timestamps', () async {
    await _appendAccountEvents(eventStore);
    final aggregate = await runtime.resolve(_envelopeAggregate('account/'));
    final events = aggregate.state.events;

    expect(events.map((v) => v.streamPath), [
      'account/one',
      'account/two',
      'account/one',
    ]);
    expect(events.map((v) => v.actor), everyElement('test-actor'));
    expect(events.map((v) => v.occuredAt), [
      _timestamp,
      _timestamp.add(const Duration(days: 1)),
      _timestamp.add(const Duration(days: 3)),
    ]);
  });

  test('snapshot exposes the current state and nullable sequence', () async {
    final aggregate = _envelopeAggregate('account/one');
    expect(aggregate.snapshot().sequence, isNull);
    await _appendAccountEvents(eventStore);
    await runtime.resolve(aggregate);

    final snapshot = aggregate.snapshot();
    expect(snapshot.state, same(aggregate.state));
    expect(snapshot.sequence, 3);
  });

  test('stateless resolution returns the final matching sequence', () async {
    await _appendAccountEvents(eventStore);
    final values = <String>[];
    final sequence = await runtime.resolveStateless<_TestEvent>(
      filter: const PatternFilter.exact('account/one'),
      apply: (envelope) => values.add(envelope.event.value),
    );

    expect(values, ['opened', 'deposit']);
    expect(sequence, 3);
    expect(
      await runtime.resolveStateless<_TestEvent>(
        filter: const PatternFilter.exact('account/one'),
        apply: (envelope) => values.add(envelope.event.value),
        sequence: sequence,
      ),
      3,
    );
    expect(values, ['opened', 'deposit']);
  });

  test('resolution diagnostics omit event payloads', () async {
    await _appendAccountEvents(eventStore);
    final logger = RecordingLogger();
    final observed = CqrsRuntime(
      actor: 'test-actor',
      eventStore: eventStore,
      logger: logger,
      timeProvider: FakeTimeProviderStatic.zero(),
      notificationBus: MemoryNotificationBus(),
    );
    observed.eventRegistry
      ..add(const _TestEventCodec())
      ..freeze();

    await observed.resolve(_envelopeAggregate('account/one'));
    await observed.resolveStateless<_TestEvent>(
      filter: const PatternFilter.exact('account/one'),
      apply: (_) {},
    );

    final messages = logger.entries.map((entry) => entry.message).join(' ');
    expect(messages, isNot(contains('opened')));
    expect(messages, isNot(contains('deposit')));
    expect(
      EventEnvelope(
        actor: 'a',
        streamPath: 'account/one',
        event: const _TestEvent('secret', 'one'),
        occuredAt: _timestamp,
      ).toString(),
      isNot(contains('secret')),
    );
  });

  test(
    'state application failure leaves the event available for retry',
    () async {
      await _appendAccountEvents(eventStore);
      final aggregate = _envelopeAggregate('account/one');
      aggregate.state.failNext = true;
      await expectLater(runtime.resolve(aggregate), throwsStateError);
      expect(aggregate.state.events, isEmpty);
      expect(aggregate.sequence, isNull);
      await runtime.resolve(aggregate);
      expect(aggregate.state.events.map((v) => v.event.value), [
        'opened',
        'deposit',
      ]);
    },
  );
}

Aggregate<_TestEvent, _EnvelopeState> _envelopeAggregate(String path) =>
    Aggregate(
      name: 'Events $path',
      filter:
          path.endsWith('/')
              ? PatternFilter.startsWith(path)
              : PatternFilter.exact(path),
      state: _EnvelopeState(),
    );

final class _EnvelopeState implements AggregateState<_TestEvent> {
  final events = <EventEnvelope<_TestEvent>>[];
  bool failNext = false;

  @override
  void apply(EventEnvelope<_TestEvent> envelope) {
    if (failNext) {
      failNext = false;
      throw StateError('State application failed');
    }
    events.add(envelope);
  }
}

Future<void> _appendAccountEvents(EventStore eventStore) =>
    eventStore.saveChanges(
      CommandChanges(
        actor: 'test-actor',
        dependency: CommandDependency(),
        occuredAt: _timestamp,
        locks: const [
          StreamLock(streamPath: 'account/one', originatingStreamVersion: null),
          StreamLock(streamPath: 'account/two', originatingStreamVersion: null),
          StreamLock(streamPath: 'other/three', originatingStreamVersion: null),
        ],
        events: [
          for (final (index, path, value) in [
            (0, 'account/one', 'opened'),
            (1, 'account/two', 'opened'),
            (2, 'other/three', 'ignored'),
            (3, 'account/one', 'deposit'),
          ])
            EventAppend(
              streamPath: path,
              encodedEvent: EncodedEvent(
                kind: 'test-event',
                bytes: const _TestEventCodec().toBytes(
                  _TestEvent(value, path.split('/').last),
                ),
              ),
              occuredAt: _timestamp.add(Duration(days: index)),
            ),
        ],
      ),
    );

final class _TestEvent {
  final String value;
  final String accountId;

  const _TestEvent(this.value, this.accountId);

  @override
  String toString() => value;
}

final class _TestEventCodec implements EventCodec<_TestEvent> {
  const _TestEventCodec();

  @override
  String get kind => 'test-event';

  @override
  _TestEvent fromBytes(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return _TestEvent(json['value'] as String, json['accountId'] as String);
  }

  @override
  Uint8List toBytes(_TestEvent event) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({'value': event.value, 'accountId': event.accountId}),
    ),
  );
}
