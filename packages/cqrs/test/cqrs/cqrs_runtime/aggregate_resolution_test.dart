import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  late EventStore eventStore;
  late CqrsRuntime runtime;
  late _MemorySnapshotter snapshotter;

  setUp(() {
    eventStore = EventStore(_PagedMemoryEventDatabase(1));

    runtime = CqrsRuntime(
      eventStore: eventStore,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );

    runtime.eventRegistry
      ..add(const _TestEventCodec())
      ..freeze();

    snapshotter = _MemorySnapshotter();
  });

  test('resolves selected events into fresh state on every call', () async {
    final aggregate = _EnvelopeAggregate('one');
    expect(await runtime.resolve(aggregate, 'one'), isEmpty);
    await _appendAccountEvents(eventStore);

    final first = await runtime.resolve(aggregate, 'one');
    final second = await runtime.resolve(aggregate, 'one');

    expect(first.map((envelope) => envelope.event.value), [
      'opened',
      'deposit',
    ]);
    expect(second.map((envelope) => envelope.event.value), [
      'opened',
      'deposit',
    ]);
    expect(identical(first, second), isFalse);
    expect(identical(first.first, second.first), isFalse);
  });

  test('uses log paths, parameters, timestamps, and positions', () async {
    await _appendAccountEvents(eventStore);

    final events = await runtime.resolve(_EnvelopeAggregate(null), 'unused');

    expect(events.map((envelope) => envelope.streamPath), [
      'account/one',
      'account/two',
      'account/one',
    ]);
    expect(events.map((envelope) => envelope.streamParams), [
      'one',
      'two',
      'one',
    ]);
    expect(events.map((envelope) => envelope.occuredAt), [
      _timestamp,
      _timestamp.add(const Duration(days: 1)),
      _timestamp.add(const Duration(days: 3)),
    ]);
  });

  group('snapshots', () {
    test('saves a snapshot after the first event', () async {
      await eventStore.saveChanges(
        CommandChanges(
          dependency: VersionVector(),
          encoded: EncodedCommand(kind: 'seed', bytes: Uint8List(0)),
          startedAt: _timestamp,
          completedAt: _timestamp,
          locks: const [
            StreamLock(
              streamPath: 'account/one',
              originatingStreamVersion: null,
            ),
          ],
          events: [
            EventAppend(
              streamPath: 'account/one',
              encodedEvent: EncodedEvent(
                kind: 'test-event',
                bytes: const _TestEventCodec().toBytes(_TestEvent('opened')),
              ),
              occuredAt: _timestamp,
            ),
          ],
        ),
      );

      final result = await runtime.resolve(
        _EnvelopeAggregate('one', snapshotter: snapshotter),
        'one',
      );

      expect(result, hasLength(1));
      expect(snapshotter.snapshots[1]!.sequence, 0);
    });

    test('saves at the last accepted event sequence', () async {
      await _appendAccountEvents(eventStore);

      final result = await runtime.resolve(
        _EnvelopeAggregate('two', snapshotter: snapshotter),
        'two',
      );

      expect(result.map((event) => event.streamParams), ['two']);
      expect(snapshotter.loadedVersions, [1]);
      expect(snapshotter.savedVersions, [1]);
      expect(snapshotter.snapshots[1]!.sequence, 1);
      expect(snapshotter.snapshots[1]!.state, result);
    });

    test('resumes after a snapshot across filtered pages', () async {
      await _appendAccountEvents(eventStore);
      final history = await runtime.resolve(_EnvelopeAggregate('one'), 'one');
      snapshotter.snapshots[1] = Snapshot([history.first], 0);
      final aggregate = _EnvelopeAggregate('one', snapshotter: snapshotter);

      final result = await runtime.resolve(aggregate, 'one');

      expect(result.map((event) => event.event.value), ['opened', 'deposit']);
      expect(snapshotter.snapshots[1]!.sequence, 3);
    });

    test('does not save an empty selection', () async {
      await _appendAccountEvents(eventStore);

      final result = await runtime.resolve(
        _EnvelopeAggregate('missing', snapshotter: snapshotter),
        'missing',
      );

      expect(result, isEmpty);
      expect(snapshotter.savedVersions, isEmpty);
    });

    test('does not rewrite a snapshot without new accepted events', () async {
      await _appendAccountEvents(eventStore);
      final aggregate = _EnvelopeAggregate('two', snapshotter: snapshotter);
      await runtime.resolve(aggregate, 'two');
      snapshotter.savedVersions.clear();

      final result = await runtime.resolve(aggregate, 'two');

      expect(result, hasLength(1));
      expect(snapshotter.savedVersions, isEmpty);
    });

    test('forced replay bypasses snapshot loading and saving', () async {
      await _appendAccountEvents(eventStore);
      snapshotter.snapshots[1] = const Snapshot([], 4);
      final aggregate = _EnvelopeAggregate('one', snapshotter: snapshotter);

      final result = await runtime.resolve(
        aggregate,
        'one',
        forceResolveFromEvents: true,
      );

      expect(result.map((event) => event.event.value), ['opened', 'deposit']);
      expect(snapshotter.loadedVersions, isEmpty);
      expect(snapshotter.savedVersions, isEmpty);
    });

    test('replays when the aggregate version changes', () async {
      await _appendAccountEvents(eventStore);
      snapshotter.snapshots[1] = const Snapshot([], 4);
      final aggregate = _EnvelopeAggregate(
        'one',
        snapshotter: snapshotter,
        version: 2,
      );

      final result = await runtime.resolve(aggregate, 'one');

      expect(result, hasLength(2));
      expect(snapshotter.loadedVersions, [2]);
      expect(snapshotter.savedVersions, [2]);
      expect(snapshotter.snapshots[1]!.state, isEmpty);
    });

    test('replays when snapshot loading throws an Exception', () async {
      await _appendAccountEvents(eventStore);
      snapshotter.loadFailure = Exception('load unavailable');

      final result = await runtime.resolve(
        _EnvelopeAggregate('one', snapshotter: snapshotter),
        'one',
      );

      expect(result.map((event) => event.event.value), ['opened', 'deposit']);
      expect(snapshotter.savedVersions, [1]);
    });

    test('returns resolved state when saving throws an Exception', () async {
      await _appendAccountEvents(eventStore);
      snapshotter.saveFailure = Exception('save unavailable');

      final result = await runtime.resolve(
        _EnvelopeAggregate('one', snapshotter: snapshotter),
        'one',
      );

      expect(result.map((event) => event.event.value), ['opened', 'deposit']);
      expect(snapshotter.savedVersions, [1]);
    });

    test('does not save partial state after replay fails', () async {
      await _appendAccountEvents(eventStore);
      final failure = StateError('apply failed');
      final aggregate = _EnvelopeAggregate(
        'one',
        snapshotter: snapshotter,
        applyFailure: failure,
      );

      await expectLater(
        runtime.resolve(aggregate, 'one'),
        throwsA(same(failure)),
      );

      expect(snapshotter.savedVersions, isEmpty);
    });

    test('caller mutation does not alter a saved snapshot', () async {
      await _appendAccountEvents(eventStore);
      final aggregate = _EnvelopeAggregate('one', snapshotter: snapshotter);
      final first = await runtime.resolve(aggregate, 'one');
      first.clear();
      final second = await runtime.resolve(aggregate, 'one');
      second.clear();

      final third = await runtime.resolve(aggregate, 'one');

      expect(third.map((event) => event.event.value), ['opened', 'deposit']);
    });
  });
}

Future<void> _appendAccountEvents(EventStore eventStore) =>
    eventStore.saveChanges(
      CommandChanges(
        dependency: VersionVector(),
        encoded: EncodedCommand(kind: 'seed', bytes: Uint8List(0)),
        startedAt: _timestamp,
        completedAt: _timestamp,
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
                bytes: const _TestEventCodec().toBytes(_TestEvent(value)),
              ),
              occuredAt: _timestamp.add(Duration(days: index)),
            ),
        ],
      ),
    );

final class _TestEvent {
  final String value;

  const _TestEvent(this.value);
}

final class _TestEventCodec implements EventCodec<_TestEvent> {
  const _TestEventCodec();

  @override
  String get kind => 'test-event';

  @override
  _TestEvent fromBytes(Uint8List bytes) => _TestEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(_TestEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));
}

final class _EnvelopeAggregate
    implements
        Aggregate<_TestEvent, String, List<EventEnvelope<_TestEvent, String>>> {
  final String? selectedAccount;

  @override
  final Snapshotter<List<EventEnvelope<_TestEvent, String>>>? snapshotter;

  final Object? applyFailure;

  _EnvelopeAggregate(
    this.selectedAccount, {
    this.snapshotter,
    this.version = 1,
    this.applyFailure,
  });

  @override
  final int version;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('account/*');

  @override
  List<EventEnvelope<_TestEvent, String>> initialState() => [];

  @override
  bool canApply(EventEnvelope<_TestEvent, String> envelope) =>
      selectedAccount == null || envelope.streamParams == selectedAccount;

  @override
  void apply(
    List<EventEnvelope<_TestEvent, String>> state,
    EventEnvelope<_TestEvent, String> envelope,
  ) {
    state.add(envelope);
    if (applyFailure != null) throw applyFailure!;
  }
}

final class _PagedMemoryEventDatabase extends MemoryEventDatabase {
  final int pageSize;

  _PagedMemoryEventDatabase(this.pageSize);

  @override
  int get defaultEventFetchPageSize => pageSize;
}

final class _MemorySnapshotter
    implements Snapshotter<List<EventEnvelope<_TestEvent, String>>> {
  final snapshots = <int, Snapshot<List<EventEnvelope<_TestEvent, String>>>>{};
  final loadedVersions = <int>[];
  final savedVersions = <int>[];
  Exception? loadFailure;
  Exception? saveFailure;

  @override
  Future<Snapshot<List<EventEnvelope<_TestEvent, String>>>?> load(
    int aggregateVersion,
  ) async {
    loadedVersions.add(aggregateVersion);
    if (loadFailure != null) throw loadFailure!;
    final snapshot = snapshots[aggregateVersion];
    return snapshot == null
        ? null
        : Snapshot(List.of(snapshot.state), snapshot.sequence);
  }

  @override
  Future<void> save(
    int aggregateVersion,
    Snapshot<List<EventEnvelope<_TestEvent, String>>> snapshot,
  ) async {
    savedVersions.add(aggregateVersion);
    if (saveFailure != null) throw saveFailure!;
    snapshots[aggregateVersion] = Snapshot(
      List.of(snapshot.state),
      snapshot.sequence,
    );
  }
}
