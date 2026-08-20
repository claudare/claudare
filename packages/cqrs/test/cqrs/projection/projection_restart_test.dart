import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:id_generator/id_generator.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

typedef _BackendSetup =
    ({Future<_Session> Function() open, Future<void> Function() cleanup});

Future<void> _testRestarts(
  String name,
  Future<_BackendSetup> Function() setup,
) async {
  group('selective projection restart - $name', () {
    late Future<_Session> Function() open;
    late Future<void> Function() cleanup;

    setUp(() async {
      final backend = await setup();
      open = backend.open;
      cleanup = backend.cleanup;
    });

    tearDown(() async {
      await cleanup();
    });

    // TODO: this test needs to be split into multiple tests
    test(
      'adding, changing, and interrupting reset only one projection',
      () async {
        final firstState = _ProjectionState();
        final secondState = _ProjectionState();

        var session = await open();
        await _appendEvent(session.eventStore);
        await _initialize(session, [
          _RecordingProjection('first', 1, firstState),
        ]);
        await session.close();

        expect(firstState.resetCount, 1);
        expect(firstState.values, ['event']);

        session = await open();
        await _initialize(session, [
          _RecordingProjection('first', 1, firstState),
          _RecordingProjection('second', 1, secondState),
        ]);
        await session.close();

        expect(firstState.resetCount, 1);
        expect(firstState.values, ['event']);
        expect(secondState.resetCount, 1);
        expect(secondState.values, ['event']);

        session = await open();
        await _initialize(session, [
          _RecordingProjection('first', 2, firstState),
          _RecordingProjection('second', 1, secondState),
        ]);
        await session.close();

        expect(firstState.resetCount, 2);
        expect(firstState.values, ['event']);
        expect(secondState.resetCount, 1);
        expect(secondState.values, ['event']);

        session = await open();
        final store = RuntimeStore(session.runtimeDatabase);
        await store.initialize();
        final interruption = StateError('interrupted page');
        await expectLater(
          store.advanceProjection(
            'second',
            1,
            2,
            () async => throw interruption,
          ),
          throwsA(same(interruption)),
        );
        await session.close();

        session = await open();
        await _initialize(session, [
          _RecordingProjection('first', 2, firstState),
          _RecordingProjection('second', 1, secondState),
        ]);
        final firstPosition =
            await RuntimeStore(
                  session.runtimeDatabase,
                ).getProjectionPosition('first')
                as ProjectionAtSequence;
        final secondPosition =
            await RuntimeStore(
                  session.runtimeDatabase,
                ).getProjectionPosition('second')
                as ProjectionAtSequence;
        await session.close();

        expect(firstState.resetCount, 2);
        expect(firstState.values, ['event']);
        expect(secondState.resetCount, 2);
        expect(secondState.values, ['event']);
        expect(firstPosition.version, 2);
        expect(firstPosition.scannedThroughLocalSequence, 1);
        expect(secondPosition.version, 1);
        expect(secondPosition.scannedThroughLocalSequence, 1);
      },
    );
  });
}

void main() async {
  await _testRestarts('memory', () async {
    final eventDatabase = MemoryEventDatabase();
    final runtimeDatabase = MemoryRuntimeDatabase();

    Future<_Session> open() async {
      final eventStore = EventStore(eventDatabase);
      await eventStore.migrate();
      return _Session(
        eventStore: eventStore,
        runtimeDatabase: runtimeDatabase,
        close: eventStore.close,
      );
    }

    return (open: open, cleanup: () async {});
  });

  await _testRestarts('sqlite', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cqrs_projection_restart_',
    );
    final databasePath = '${directory.path}/runtime.sqlite';

    Future<_Session> open() async {
      final database = IsolateSqlite();
      await database.open(databasePath);
      final eventStore = EventStore(SqliteEventDatabase(database));
      await eventStore.migrate();
      return _Session(
        eventStore: eventStore,
        runtimeDatabase: SqliteRuntimeDatabase(database),
        close: eventStore.close,
      );
    }

    return (open: open, cleanup: () async => directory.delete(recursive: true));
  });
}

Future<void> _initialize(
  _Session session,
  List<Projection<_RestartEvent, String>> projections,
) async {
  final eventRegistry = EventRegistry()..add(const _RestartEventCodec());
  final projectionRegistry = ProjectionRegistry();
  for (final projection in projections) {
    projectionRegistry.add(projection);
  }
  final runtime = CqrsRuntime(
    dependencies: CqrsRuntimeDependencies(
      eventStore: session.eventStore,
      runtimeDatabase: session.runtimeDatabase,
      logger: const NoopLogger(),
      idGenerator: IdGeneratorSequential(),
      timeProvider: FakeTimeProviderStatic.zero(),
    ),
    eventRegistry: eventRegistry,
    projectionRegistry: projectionRegistry,
    runtimeName: 'restart-test',
  );
  await runtime.initialize();
}

Future<void> _appendEvent(EventStore eventStore) async {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  const codec = _RestartEventCodec();
  await eventStore.saveChanges(
    CommandChanges(
      encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
      startedAt: occurredAt,
      completedAt: occurredAt,
      locks: const [
        StreamLocalLock(streamPath: 'match/one', originatingStreamVersion: 0),
      ],
      events: [
        EventAppend(
          streamPath: 'match/one',
          encodedEvent: EncodedEvent(
            kind: codec.kind,
            bytes: codec.toBytes(const _RestartEvent('event')),
          ),
          occuredAt: occurredAt,
        ),
      ],
    ),
  );
}

final class _Session {
  final EventStore eventStore;
  final RuntimeDatabase runtimeDatabase;
  final Future<void> Function() close;

  const _Session({
    required this.eventStore,
    required this.runtimeDatabase,
    required this.close,
  });
}

final class _ProjectionState {
  final values = <String>[];
  int resetCount = 0;
}

// TODO: this need to be reused across test. Its a pretty good fake projection
// implementation
final class _RecordingProjection implements Projection<_RestartEvent, String> {
  @override
  final String name;
  @override
  final int version;
  final _ProjectionState state;

  const _RecordingProjection(this.name, this.version, this.state);

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('match/*');

  @override
  Future<void> reset() async {
    state.resetCount++;
    state.values.clear();
  }

  @override
  Future<void> apply(
    String streamParams,
    _RestartEvent event,
    EventMetadata metadata,
  ) async {
    state.values.add(event.value);
  }

  @override
  void onBatchApplied() {}
}

final class _RestartEvent {
  final String value;

  const _RestartEvent(this.value);
}

final class _RestartEventCodec implements EventCodec<_RestartEvent> {
  const _RestartEventCodec();

  @override
  String get kind => 'projection-restart-test';

  @override
  _RestartEvent fromBytes(Uint8List bytes) => _RestartEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(_RestartEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));
}
