import 'package:id_generator/id_generator.dart';

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
      idGenerator: IdGeneratorSequential(),
      actor: 'test-actor',
      eventStore: eventStore,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    runtime.eventRegistry.add(const _TestEventCodec());
  });

  test('resolves matching events and resumes across filtered pages', () async {
    final aggregate = _envelopeAggregate('account/one');
    expect((await runtime.resolve(aggregate)).state.events, isEmpty);
    expect(aggregate.sequence, -1);

    await _appendAccountEvents(eventStore);
    expect(identical(await runtime.resolve(aggregate), aggregate), isTrue);
    expect(aggregate.state.events.map((v) => v.event.value), [
      'opened',
      'deposit',
    ]);
    expect(aggregate.state.events.map((v) => v.logPosition), [0, 3]);
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
    expect(events.map((v) => v.logPosition), [0, 1, 3]);
    expect(events.map((v) => v.occuredAt), [
      _timestamp,
      _timestamp.add(const Duration(days: 1)),
      _timestamp.add(const Duration(days: 3)),
    ]);
  });

  test('snapshot exposes the current state and sequence', () async {
    final aggregate = _envelopeAggregate('account/one');
    expect(aggregate.snapshot().sequence, -1);
    await _appendAccountEvents(eventStore);
    await runtime.resolve(aggregate);

    final snapshot = aggregate.snapshot();
    expect(snapshot.state, same(aggregate.state));
    expect(snapshot.sequence, 3);
  });

  test('resolution diagnostics omit event payloads', () async {
    await _appendAccountEvents(eventStore);
    final logger = RecordingLogger();
    final observed = CqrsRuntime(
      idGenerator: IdGeneratorSequential(),
      actor: 'test-actor',
      eventStore: eventStore,
      logger: logger,
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    observed.eventRegistry.add(const _TestEventCodec());

    await observed.resolve(_envelopeAggregate('account/one'));

    final messages = logger.entries.map((entry) => entry.message).join(' ');
    expect(messages, isNot(contains('opened')));
    expect(messages, isNot(contains('deposit')));
    expect(
      EventEnvelope(
        actor: 'a',
        streamPath: 'account/one',
        event: const _TestEvent('secret', 'one'),
        occuredAt: _timestamp,
        logPosition: 0,
      ).toString(),
      isNot(contains('secret')),
    );
  });

  test('read failure retains the last successfully handled position', () async {
    final store = _InterruptedMemoryEventStore();
    final observed = CqrsRuntime(
      idGenerator: IdGeneratorSequential(),
      actor: 'test-actor',
      eventStore: store,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    observed.eventRegistry.add(const _TestEventCodec());
    await _appendAccountEvents(store);
    final aggregate = _envelopeAggregate('account/one');

    store.failAt = 1;
    await expectLater(observed.resolve(aggregate), throwsException);
    expect(aggregate.state.events.map((v) => v.event.value), ['opened']);
    expect(aggregate.state.events.single.logPosition, 0);
    expect(aggregate.sequence, 0);

    store.reads.clear();
    await observed.resolve(aggregate);
    expect(store.reads.first, 1);
    expect(aggregate.state.events.map((v) => v.event.value), [
      'opened',
      'deposit',
    ]);
    expect(aggregate.state.events.map((v) => v.logPosition), [0, 3]);
    expect(aggregate.sequence, 3);
  });

  test(
    'state application failure leaves the event available for retry',
    () async {
      await _appendAccountEvents(eventStore);
      final aggregate = _envelopeAggregate('account/one');
      aggregate.state.failNext = true;
      await expectLater(runtime.resolve(aggregate), throwsStateError);
      expect(aggregate.state.events, isEmpty);
      expect(aggregate.sequence, -1);
      await runtime.resolve(aggregate);
      expect(aggregate.state.events.map((v) => v.event.value), [
        'opened',
        'deposit',
      ]);
      expect(aggregate.state.events.map((v) => v.logPosition), [0, 3]);
    },
  );
}

final class _InterruptedMemoryEventStore extends MemoryEventStore {
  final List<int> reads = [];
  int? failAt;

  _InterruptedMemoryEventStore() : super(eventFetchPageSize: 1);

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) {
    reads.add(fromPosition);
    if (failAt == fromPosition) {
      failAt = null;
      return Future.error(Exception('Interrupted event read'));
    }
    return super.getLogEvents(filter, fromPosition);
  }
}

Aggregate<_TestEvent, _EnvelopeState> _envelopeAggregate(String path) =>
    Aggregate(
      name: 'Events $path',
      filter: path.endsWith('/')
          ? LogFilter.startsWith(path)
          : LogFilter.exact(path),
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

  @override
  void onStreamDeleted(StreamDeletion deletion) {}
}

Future<void> _appendAccountEvents(EventStore eventStore) =>
    eventStore.saveChanges(
      CommandChanges(
        actor: 'test-actor',
        dependency: CommandDependency(),
        occuredAt: _timestamp,
        locks: const [
          StreamLock(streamPath: 'account/one', originatingStreamVersion: -1),
          StreamLock(streamPath: 'account/two', originatingStreamVersion: -1),
          StreamLock(streamPath: 'other/three', originatingStreamVersion: -1),
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
