import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:test/test.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  late EventStore eventStore;
  late _CountingRuntimeDatabase runtimeDatabase;
  late RuntimeStore runtimeStore;
  late EventRegistry eventRegistry;

  setUp(() async {
    eventStore = EventStore(MemoryEventDatabase(), eventFetchPageSize: 10);
    await eventStore.migrate();
    runtimeDatabase = _CountingRuntimeDatabase();
    runtimeStore = RuntimeStore(runtimeDatabase);
    await runtimeStore.initialize();
    eventRegistry = EventRegistry()..add(const _TestEventCodec());
  });

  ProjectionRuntime<_TestEvent, String> runner(
    _RecordingProjection projection,
  ) {
    return ProjectionRuntime(
      projection,
      logger: const NoopLogger(),
      runtimeName: 'test',
      runtimeStore: runtimeStore,
      eventRegistry: eventRegistry,
    );
  }

  Future<void> append(List<({String path, String value})> events) {
    final paths = events.map((event) => event.path).toSet();
    return eventStore
        .saveChanges(
          CommandChanges(
            encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
            startedAt: occurredAt,
            completedAt: occurredAt,
            locks: [
              for (final path in paths)
                StreamLocalLock(streamPath: path, originatingStreamVersion: 0),
            ],
            events: [
              for (final event in events)
                EventAppend(
                  streamPath: event.path,
                  encodedEvent: eventRegistry.encode(_TestEvent(event.value)),
                  occuredAt: occurredAt,
                ),
            ],
          ),
        )
        .then((_) {});
  }

  test('commits multiple matching events as one projection page', () async {
    await append([
      (path: 'match/one', value: 'first'),
      (path: 'match/two', value: 'second'),
    ]);
    final projection = _RecordingProjection();

    await runner(projection).catchupSelfLoad(eventStore);

    expect(projection.calls, ['one:first', 'two:second']);
    expect(runtimeDatabase.setStateCount, 4);
    final position =
        await runtimeStore.getProjectionPosition(projection.name)
            as ProjectionAtSequence;
    expect(position.version, 1);
    expect(position.scannedThroughLocalSequence, 2);
  });

  test(
    'applies matching events and advances through unrelated events',
    () async {
      await append([
        (path: 'unrelated/one', value: 'ignored'),
        (path: 'match/two', value: 'applied'),
        (path: 'unrelated/three', value: 'ignored'),
      ]);
      final projection = _RecordingProjection();

      await runner(projection).catchupSelfLoad(eventStore);

      expect(projection.calls, ['two:applied']);
      final position =
          await runtimeStore.getProjectionPosition(projection.name)
              as ProjectionAtSequence;
      expect(position.scannedThroughLocalSequence, 3);
    },
  );

  test('advances a page with no route matches to the page end', () async {
    await append([
      (path: 'unrelated/one', value: 'ignored'),
      (path: 'unrelated/two', value: 'ignored'),
    ]);
    final projection = _RecordingProjection();

    await runner(projection).catchupSelfLoad(eventStore);

    expect(projection.calls, isEmpty);
    expect(runtimeDatabase.setStateCount, 4);
    final position =
        await runtimeStore.getProjectionPosition(projection.name)
            as ProjectionAtSequence;
    expect(position.scannedThroughLocalSequence, 2);
  });

  test(
    'restart resumes without resetting or reapplying completed pages',
    () async {
      await append([(path: 'match/one', value: 'once')]);
      final projection = _RecordingProjection();
      await runner(projection).catchupSelfLoad(eventStore);

      await runner(projection).catchupSelfLoad(eventStore);

      expect(projection.resetCount, 1);
      expect(projection.calls, ['one:once']);
    },
  );

  test('restart resets and rebuilds an interrupted projection', () async {
    await append([(path: 'match/one', value: 'replayed')]);
    final projection = _RecordingProjection();
    await runner(projection).catchupSelfLoad(eventStore);
    final error = StateError('interrupted');
    await expectLater(
      runtimeStore.advanceProjection(
        projection.name,
        1,
        2,
        () async => throw error,
      ),
      throwsA(same(error)),
    );

    await runner(projection).catchupSelfLoad(eventStore);

    expect(projection.resetCount, 2);
    expect(projection.calls, ['one:replayed']);
    final position =
        await runtimeStore.getProjectionPosition(projection.name)
            as ProjectionAtSequence;
    expect(position.scannedThroughLocalSequence, 1);
  });

  test('replay failure leaves the projection inconsistent', () async {
    await append([(path: 'match/one', value: 'fails')]);
    final projection = _RecordingProjection(failOnApply: true);

    await runner(projection).catchupSelfLoad(eventStore);

    expect(projection.failureHandler.hasErrored(), isTrue);
    expect(
      await runtimeStore.getProjectionPosition(projection.name),
      isA<ProjectionInconsistent>(),
    );
  });

  test('live delivery keeps direct matching-event progress', () async {
    final projection = _RecordingProjection();
    final projectionRunner = runner(projection);
    await projectionRunner.catchupSelfLoad(eventStore);
    final done = Completer<void>();

    projectionRunner.enqueue(
      EventEnvelope(
        streamPath: 'match/live',
        encodedEvent: eventRegistry.encode(const _TestEvent('event')),
        occuredAt: occurredAt,
        localSequence: 5,
      ),
      onDone: done.complete,
    );
    await done.future;

    expect(projection.calls, ['live:event']);
    final position =
        await runtimeStore.getProjectionPosition(projection.name)
            as ProjectionAtSequence;
    expect(position.scannedThroughLocalSequence, 5);
  });
}

final class _TestEvent {
  final String value;

  const _TestEvent(this.value);
}

final class _TestEventCodec implements EventCodec<_TestEvent> {
  const _TestEventCodec();

  @override
  String get kind => 'projection-runtime-test';

  @override
  _TestEvent fromBytes(Uint8List bytes) => _TestEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(_TestEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));
}

final class _RecordingProjection implements Projection<_TestEvent, String> {
  final bool failOnApply;
  @override
  final failureHandler = StandardProjectionFailureHandler();
  final calls = <String>[];
  int resetCount = 0;

  _RecordingProjection({this.failOnApply = false});

  @override
  String get name => 'recording';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('match/*');

  @override
  Future<void> reset() async {
    resetCount++;
    calls.clear();
  }

  @override
  Future<void> apply(
    String streamParams,
    _TestEvent event,
    EventMetadata metadata,
  ) async {
    if (failOnApply) throw Exception('apply failed');
    calls.add('$streamParams:${event.value}');
  }

  @override
  void onBatchApplied() {}
}

final class _CountingRuntimeDatabase extends MemoryRuntimeDatabase {
  int setStateCount = 0;

  @override
  Future<void> setProjectionState(String name, RuntimeProjectionState state) {
    setStateCount++;
    return super.setProjectionState(name, state);
  }
}
