import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test('work before initialization throws StateError synchronously', () async {
    final runtime = CqrsRuntime(
      dependencies: CqrsRuntimeDependencies(
        eventStore: EventStore(MemoryEventDatabase()),
        runtimeDatabase: MemoryRuntimeDatabase(),
        logger: const NoopLogger(),
        idGenerator: IdGeneratorSequential(),
        timeProvider: FakeTimeProviderStatic.zero(),
      ),
      eventRegistry: EventRegistry(),
      projectionRegistry: ProjectionRegistry(),
      runtimeName: 'empty',
    );

    expect(runtime.pump, throwsStateError);
    expect(
      () => runtime.execute(const _NoEventCommand(), const _Input('unused')),
      throwsStateError,
    );
    expect(runtime.recreateProjections, throwsStateError);
    await runtime.close();
    await runtime.close();
  });

  test('initialization can only be requested once', () async {
    final migrationStarted = Completer<void>();
    final releaseMigration = Completer<void>();
    final runtime = _runtime(
      eventStore: _BlockingMigrationEventStore(
        migrationStarted,
        releaseMigration,
      ),
      projection: _RecordingProjection(),
    );

    final initialization = runtime.initialize();
    await migrationStarted.future;
    expect(runtime.initialize, throwsStateError);
    expect(runtime.pump, throwsStateError);
    releaseMigration.complete();
    await initialization;
    expect(runtime.initialize, throwsStateError);
    await runtime.close();
  });

  test(
    'initializes, pumps startup history, freezes registration, and closes',
    () async {
      final eventStore = EventStore(MemoryEventDatabase());
      await eventStore.migrate();
      await _appendDirect(eventStore, 'startup');
      final projection = _RecordingProjection();
      final eventRegistry = EventRegistry();
      final projectionRegistry = ProjectionRegistry();
      final runtime = _runtime(
        eventStore: eventStore,
        projection: projection,
        eventRegistry: eventRegistry,
        projectionRegistry: projectionRegistry,
      );

      await runtime.initialize();

      expect(projection.values, ['startup']);
      expect(projection.resetCount, 1);
      expect(
        () => eventRegistry.add(const _OtherEventCodec()),
        throwsA(isA<EventRegistryException>()),
      );
      expect(
        () => projectionRegistry.add(_RecordingProjection()),
        throwsA(isA<ProjectionConfigurationException>()),
      );

      final firstClose = runtime.close();
      expect(runtime.close(), same(firstClose));
      await firstClose;
      expect(runtime.pump, throwsStateError);
    },
  );

  test('command completion waits for durability but not projections', () async {
    final applied = Completer<void>();
    final release = Completer<void>();
    final projection = _RecordingProjection(
      onApply: (event) async {
        applied.complete();
        await release.future;
      },
    );
    final eventStore = EventStore(MemoryEventDatabase());
    final runtime = _runtime(eventStore: eventStore, projection: projection);
    await runtime.initialize();
    addTearDown(() => _settle(runtime.close()));

    await runtime.execute(const _AppendCommand(), const _Input('durable'));
    expect((await eventStore.getAppliedCommands(0)), hasLength(1));
    await applied.future;

    var pumpCompleted = false;
    final pumping = runtime.pump().then((_) => pumpCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(pumpCompleted, isFalse);

    release.complete();
    await pumping;
    expect(projection.values, ['durable']);
  });

  test(
    'expected command and concurrency failures leave runtime running',
    () async {
      final runtime = _runtime(
        eventStore: _ConcurrencyEventStore(),
        projection: _RecordingProjection(),
      );
      await runtime.initialize();
      addTearDown(() => _settle(runtime.close()));
      final rejection = Exception('rejected');

      await expectLater(
        runtime.execute(_ThrowingCommand(rejection), const _Input('unused')),
        throwsA(same(rejection)),
      );
      await expectLater(
        runtime.execute(const _AppendCommand(), const _Input('conflict')),
        throwsA(isA<ConcurrencyProblem>()),
      );

      expect(runtime.failure, isNull);
    },
  );

  test(
    'command Error is non-terminal and preserves later availability',
    () async {
      final runtime = _runtime(
        eventStore: EventStore(MemoryEventDatabase()),
        projection: _RecordingProjection(),
      );
      await runtime.initialize();
      addTearDown(() => _settle(runtime.close()));
      final error = StateError('handler bug');

      final result = await _capture(
        runtime.execute(_ThrowingObjectCommand(error), const _Input('unused')),
      );

      expect(result.error, same(error));
      expect(runtime.failure, isNull);
      await runtime.execute(const _NoEventCommand(), const _Input('later'));
    },
  );

  test(
    'startup pump failure is wrapped once and automatically closes',
    () async {
      final projectionError = StateError('projection failed');
      final eventStore = EventStore(
        MemoryEventDatabase(),
        eventFetchPageSize: 1,
      );
      await eventStore.migrate();
      await _appendDirect(eventStore, 'first');
      await _appendDirect(eventStore, 'second', streamVersion: 1);
      final projection = _RecordingProjection(failure: projectionError);
      final runtime = _runtime(eventStore: eventStore, projection: projection);
      final emitted = <CqrsRuntimeFailure>[];
      runtime.failures.listen(emitted.add);

      final initialization = await _capture(runtime.initialize());
      await Future<void>.delayed(Duration.zero);

      expect(initialization.error, isA<CqrsRuntimeFailure>());
      final failure = initialization.error as CqrsRuntimeFailure;
      expect(failure.error, same(projectionError));
      expect(
        initialization.stackTrace.toString(),
        failure.stackTrace.toString(),
      );
      expect(runtime.failure, same(failure));
      expect(emitted, [same(failure)]);
      expect(projection.applyCount, 1);

      expect(runtime.pump, throwsStateError);
      expect(runtime.initialize, throwsStateError);
      await runtime.close();
    },
  );

  test(
    'encoding failures are non-terminal and later commands remain available',
    () async {
      final codec = _ConditionalEventCodec();
      codec.shouldFail = false;
      final runtime = _runtime(
        eventStore: EventStore(MemoryEventDatabase()),
        projection: _RecordingProjection(),
        codec: codec,
      );
      await runtime.initialize();
      addTearDown(() => _settle(runtime.close()));

      await runtime.execute(const _NoEventCommand(), _ThrowingInput());

      final commandEncoding = await _capture(
        runtime.execute(const _AppendCommand(), _ThrowingInput()),
      );
      expect(commandEncoding.error, isA<CommandCodecException>());
      expect(runtime.failure, isNull);

      codec.shouldFail = true;
      final eventEncoding = await _capture(
        runtime.execute(const _AppendCommand(), const _Input('fatal')),
      );
      expect(eventEncoding.error, isA<EventCodecException>());
      expect(runtime.failure, isNull);

      codec.shouldFail = false;
      await runtime.execute(const _AppendCommand(), const _Input('later'));
      await runtime.pump();
    },
  );

  test('persistence failures are non-terminal', () async {
    final persistenceFailure = Exception('persistence failed');
    final eventStore = _PersistenceEventStore(persistenceFailure);
    final runtime = _runtime(
      eventStore: eventStore,
      projection: _RecordingProjection(),
    );
    await runtime.initialize();
    addTearDown(() => _settle(runtime.close()));

    final result = await _capture(
      runtime.execute(const _AppendCommand(), const _Input('fatal')),
    );

    expect(result.error, same(persistenceFailure));
    expect(runtime.failure, isNull);

    eventStore.shouldFail = false;
    await runtime.execute(const _AppendCommand(), const _Input('later'));
  });

  test('initialization failure preserves identity and stack trace', () async {
    final initializationFailure = StateError('runtime store failed');
    final initializationStackTrace = StackTrace.current;
    final runtime = _runtime(
      eventStore: _MigrationFailingEventStore(
        initializationFailure,
        initializationStackTrace,
      ),
      projection: _RecordingProjection(),
    );

    final result = await _capture(runtime.initialize());

    expect(result.error, same(initializationFailure));
    expect(result.stackTrace.toString(), initializationStackTrace.toString());
    expect(runtime.failure, isNull);
    expect(runtime.initialize, throwsStateError);
    await runtime.close();
  });

  test('running pump failure is retained and emitted once', () async {
    final projection = _RecordingProjection();
    final eventStore = _SilentEventStore();
    final runtime = _runtime(eventStore: eventStore, projection: projection);
    final emitted = <CqrsRuntimeFailure>[];
    runtime.failures.listen(emitted.add);
    await runtime.initialize();
    final projectionFailure = StateError('projection failed');
    projection.failure = projectionFailure;
    await _appendDirect(eventStore, 'failed');

    final result = await _capture(runtime.pump());
    await Future<void>.delayed(Duration.zero);
    final failure = result.error as CqrsRuntimeFailure;

    expect(failure.error, same(projectionFailure));
    expect(result.stackTrace.toString(), failure.stackTrace.toString());
    expect(runtime.failure, same(failure));
    expect(emitted, [same(failure)]);
    expect((await _capture(runtime.pump())).error, same(failure));
    expect(
      (await _capture(
        runtime.execute(const _NoEventCommand(), const _Input('later')),
      )).error,
      same(failure),
    );
    await runtime.close();
    expect(runtime.pump, throwsStateError);
  });

  test('projection preparation failure is raw and non-terminal', () async {
    final resetFailure = Exception('reset failed');
    final projection = _RecordingProjection();
    final runtime = _runtime(
      eventStore: EventStore(MemoryEventDatabase()),
      projection: projection,
    );
    await runtime.initialize();
    addTearDown(() => _settle(runtime.close()));
    projection.resetFailure = resetFailure;

    final result = await _capture(runtime.recreateProjections());

    expect(result.error, same(resetFailure));
    expect(runtime.failure, isNull);
    projection.resetFailure = null;
    await runtime.execute(const _NoEventCommand(), const _Input('later'));
    await runtime.pump();
  });

  test('promoted events use the signal-driven durable pump', () async {
    final eventStore = EventStore(MemoryEventDatabase());
    final projection = _RecordingProjection();
    final runtime = _runtime(eventStore: eventStore, projection: projection);
    await runtime.initialize();
    addTearDown(() => _settle(runtime.close()));

    final command = ReplicatedCommand(
      commandId: CommandId(9, 1),
      dependency: VersionVector(),
      encoded: EncodedCommand(kind: 'remote', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      eventCount: 1,
    );
    await eventStore.stageReplicatedCommand(command);
    await eventStore.stageReplicatedEvents([
      ReplicatedEvent(
        eventId: EventId(9, 1, 0),
        streamPath: 'test',
        encodedEvent: EncodedEvent(
          kind: 'test-event',
          bytes: const _TestEventCodec().toBytes(const _TestEvent('remote')),
        ),
        occuredAt: _timestamp,
      ),
    ]);
    expect(await eventStore.promotePendingCommand(command.commandId), isTrue);

    await runtime.pump();
    expect(projection.values, ['remote']);
  });

  test(
    'rebuild waits for active pumping and includes a trailing signal',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var shouldBlock = true;
      final projection = _RecordingProjection(
        onApply: (_) async {
          if (shouldBlock) {
            shouldBlock = false;
            firstStarted.complete();
            await releaseFirst.future;
          }
        },
      );
      final eventStore = EventStore(MemoryEventDatabase());
      final runtime = _runtime(eventStore: eventStore, projection: projection);
      await runtime.initialize();
      addTearDown(() => _settle(runtime.close()));

      await runtime.execute(const _AppendCommand(), const _Input('first'));
      await firstStarted.future;
      final rebuild = runtime.recreateProjections();
      await runtime.execute(const _AppendCommand(), const _Input('second'));
      releaseFirst.complete();

      await rebuild;
      expect(projection.resetCount, 2);
      expect(projection.values, ['first', 'second']);
    },
  );

  test('close waits for an active command without pumping it', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final projection = _RecordingProjection();
    final runtime = _runtime(
      eventStore: EventStore(MemoryEventDatabase()),
      projection: projection,
    );
    await runtime.initialize();

    final command = runtime.execute(
      _BlockingCommand(started, release),
      const _Input('closing'),
    );
    await started.future;
    final closing = runtime.close();
    expect(
      () => runtime.execute(const _NoEventCommand(), const _Input('later')),
      throwsStateError,
    );
    expect(runtime.pump, throwsStateError);
    expect(runtime.recreateProjections, throwsStateError);
    expect(runtime.initialize, throwsStateError);

    var closed = false;
    unawaited(closing.then((_) => closed = true));
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    await command;
    await closing;
    expect(projection.values, isEmpty);
    expect(runtime.pump, throwsStateError);
  });

  test('close during initialization throws StateError synchronously', () async {
    final migrationStarted = Completer<void>();
    final releaseMigration = Completer<void>();
    final runtime = _runtime(
      eventStore: _BlockingMigrationEventStore(
        migrationStarted,
        releaseMigration,
      ),
      projection: _RecordingProjection(),
    );

    final initialization = runtime.initialize();
    await migrationStarted.future;
    expect(runtime.close, throwsStateError);
    expect(runtime.pump, throwsStateError);
    releaseMigration.complete();
    await initialization;
    await runtime.close();
  });

  test(
    'failed initialization automatically closes after rejected close',
    () async {
      final migrationStarted = Completer<void>();
      final releaseMigration = Completer<void>();
      final failure = StateError('migration failed');
      final runtime = _runtime(
        eventStore: _BlockingFailingMigrationEventStore(
          migrationStarted,
          releaseMigration,
          failure,
        ),
        projection: _RecordingProjection(),
      );

      final initialization = runtime.initialize();
      await migrationStarted.future;
      expect(runtime.close, throwsStateError);
      releaseMigration.complete();

      expect((await _capture(initialization)).error, same(failure));
      await runtime.close();
      expect(runtime.pump, throwsStateError);
    },
  );

  test('close leaves the injected EventStore open and usable', () async {
    final eventStore = EventStore(MemoryEventDatabase());
    final projection = _RecordingProjection();
    final runtime = _runtime(eventStore: eventStore, projection: projection);
    await runtime.initialize();

    await runtime.close();
    await _appendDirect(eventStore, 'outside');

    expect((await eventStore.getAppliedCommands(0)), hasLength(1));
    expect(projection.values, isEmpty);
    await eventStore.close();
  });
}

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

CqrsRuntime _runtime({
  required EventStore eventStore,
  required Projection<_TestEvent, String> projection,
  RuntimeDatabase? runtimeDatabase,
  EventRegistry? eventRegistry,
  ProjectionRegistry? projectionRegistry,
  EventCodec<_TestEvent> codec = const _TestEventCodec(),
}) {
  final events = eventRegistry ?? EventRegistry();
  events.add(codec);
  final projections = projectionRegistry ?? ProjectionRegistry();
  projections.add(projection);
  return CqrsRuntime(
    dependencies: CqrsRuntimeDependencies(
      eventStore: eventStore,
      runtimeDatabase: runtimeDatabase ?? MemoryRuntimeDatabase(),
      logger: const NoopLogger(),
      idGenerator: IdGeneratorSequential(),
      timeProvider: FakeTimeProviderStatic.zero(),
    ),
    eventRegistry: events,
    projectionRegistry: projections,
    runtimeName: 'test',
  );
}

Future<void> _appendDirect(
  EventStore eventStore,
  String value, {
  int streamVersion = 0,
}) {
  return eventStore.saveChanges(
    CommandChanges(
      encoded: EncodedCommand(kind: 'seed', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      locks: [
        StreamLocalLock(
          streamPath: 'test',
          originatingStreamVersion: streamVersion,
        ),
      ],
      events: [
        EventAppend(
          streamPath: 'test',
          encodedEvent: EncodedEvent(
            kind: 'test-event',
            bytes: const _TestEventCodec().toBytes(_TestEvent(value)),
          ),
          occuredAt: _timestamp,
        ),
      ],
    ),
  );
}

Future<({Object error, StackTrace stackTrace})> _capture(
  Future<void> future,
) async {
  try {
    await future;
  } catch (error, stackTrace) {
    return (error: error, stackTrace: stackTrace);
  }
  throw StateError('Expected failure');
}

Future<void> _settle(Future<void> future) async {
  try {
    await future;
  } catch (_) {}
}

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

final class _OtherEventCodec implements EventCodec<int> {
  const _OtherEventCodec();

  @override
  String get kind => 'other';

  @override
  int fromBytes(Uint8List bytes) => 0;

  @override
  Uint8List toBytes(int event) => Uint8List(0);
}

final class _ConditionalEventCodec implements EventCodec<_TestEvent> {
  bool shouldFail = true;

  @override
  String get kind => 'test-event';

  @override
  _TestEvent fromBytes(Uint8List bytes) => _TestEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(_TestEvent event) {
    if (shouldFail) throw Exception('encode failed');
    return Uint8List.fromList(utf8.encode(event.value));
  }
}

class _Input implements CommandInput {
  final String value;

  const _Input(this.value);

  @override
  String get kind => 'test-command';

  @override
  Uint8List encode() => Uint8List(0);
}

final class _ThrowingInput extends _Input {
  _ThrowingInput() : super('unused');

  @override
  Uint8List encode() => throw Exception('must not encode');
}

final class _AppendCommand implements Command<_Input> {
  const _AppendCommand();

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    final stream = ctx.stream<_TestEvent>('test');
    await stream.lock();
    stream.append(_TestEvent(input.value));
  }
}

final class _NoEventCommand implements Command<_Input> {
  const _NoEventCommand();

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {}
}

final class _ThrowingCommand implements Command<_Input> {
  final Exception failure;

  const _ThrowingCommand(this.failure);

  @override
  Future<void> handle(_Input input, CommandContext ctx) async => throw failure;
}

final class _ThrowingObjectCommand implements Command<_Input> {
  final Object failure;

  const _ThrowingObjectCommand(this.failure);

  @override
  Future<void> handle(_Input input, CommandContext ctx) async => throw failure;
}

final class _BlockingCommand implements Command<_Input> {
  final Completer<void> started;
  final Completer<void> release;

  const _BlockingCommand(this.started, this.release);

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    started.complete();
    await release.future;
    final stream = ctx.stream<_TestEvent>('test');
    await stream.lock();
    stream.append(_TestEvent(input.value));
  }
}

final class _RecordingProjection implements Projection<_TestEvent, String> {
  final Future<void> Function(_TestEvent event)? onApply;
  Object? failure;
  Object? resetFailure;
  final values = <String>[];
  int resetCount = 0;
  int applyCount = 0;

  _RecordingProjection({this.onApply, this.failure});

  @override
  String get name => 'test-projection';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => const StreamRouteAll();

  @override
  Future<void> reset() async {
    resetCount++;
    final failure = resetFailure;
    if (failure != null) throw failure;
    values.clear();
  }

  @override
  Future<void> apply(
    String streamParams,
    _TestEvent event,
    EventMetadata metadata,
  ) async {
    applyCount++;
    final failure = this.failure;
    if (failure != null) throw failure;
    await onApply?.call(event);
    values.add(event.value);
  }

  @override
  void onBatchApplied() {}
}

final class _ConcurrencyEventStore extends EventStore {
  _ConcurrencyEventStore() : super(MemoryEventDatabase());

  @override
  Future<void> saveChanges(CommandChanges changes) async {
    throw const ConcurrencyProblem();
  }
}

final class _PersistenceEventStore extends EventStore {
  final Object failure;
  bool shouldFail = true;

  _PersistenceEventStore(this.failure) : super(MemoryEventDatabase());

  @override
  Future<void> saveChanges(CommandChanges changes) async {
    if (shouldFail) throw failure;
    await super.saveChanges(changes);
  }
}

final class _MigrationFailingEventStore extends EventStore {
  final Object failure;
  final StackTrace stackTrace;

  _MigrationFailingEventStore(this.failure, this.stackTrace)
    : super(MemoryEventDatabase());

  @override
  Future<void> migrate() => Future<void>.error(failure, stackTrace);
}

final class _BlockingMigrationEventStore extends EventStore {
  final Completer<void> started;
  final Completer<void> release;

  _BlockingMigrationEventStore(this.started, this.release)
    : super(MemoryEventDatabase());

  @override
  Future<void> migrate() async {
    started.complete();
    await release.future;
    await super.migrate();
  }
}

final class _BlockingFailingMigrationEventStore extends EventStore {
  final Completer<void> started;
  final Completer<void> release;
  final Object failure;

  _BlockingFailingMigrationEventStore(this.started, this.release, this.failure)
    : super(MemoryEventDatabase());

  @override
  Future<void> migrate() async {
    started.complete();
    await release.future;
    throw failure;
  }
}

final class _SilentEventStore extends EventStore {
  _SilentEventStore() : super(MemoryEventDatabase());

  @override
  Stream<void> get appliedChanges => const Stream<void>.empty();
}
