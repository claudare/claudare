import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  late MemoryEventDatabase eventDatabase;
  late EventStore eventStore;

  setUp(() async {
    eventDatabase = MemoryEventDatabase();
    eventStore = EventStore(eventDatabase);
    await eventStore.migrate();
  });

  Future<CqrsRuntime> createRuntime(
    List<Projection<_TestEvent, String>> projections, {
    Logger logger = const NoopLogger(),
  }) async {
    final projectionRegistry = ProjectionRegistry();
    for (final projection in projections) {
      projectionRegistry.add(projection);
    }

    final runtime = CqrsRuntime(
      dependencies: CqrsRuntimeDependencies(
        eventStore: eventStore,
        runtimeDatabase: MemoryRuntimeDatabase(),
        logger: logger,
        idGenerator: IdGeneratorSequential(),
        timeProvider: FakeTimeProviderStatic.zero(),
      ),
      eventRegistry: EventRegistry()..add(const _TestEventCodec()),
      projectionRegistry: projectionRegistry,
      runtimeName: 'execute-command-test',
    );
    await runtime.initializeProjections();
    return runtime;
  }

  test('persists events and routes every matching projection', () async {
    final first = _RecordingProjection('first', 'match/*');
    final second = _RecordingProjection('second', 'match/*');
    final unrelated = _RecordingProjection('unrelated', 'other/*');
    final runtime = await createRuntime([first, second, unrelated]);

    await runtime.executeCommand(
      const _AppendEventCommand(),
      const _TestInput('match/stream', 'value'),
    );
    await Future.wait([first.applied.future, second.applied.future]);

    expect(eventDatabase.testAppliedCommands, hasLength(1));
    expect(eventDatabase.testAppliedEvents, hasLength(1));
    expect(first.values, ['stream:value']);
    expect(second.values, ['stream:value']);
    expect(unrelated.values, isEmpty);
  });

  test('completes before projection processing resolves', () async {
    final projection = _BlockingProjection();
    final runtime = await createRuntime([projection]);

    await runtime.executeCommand(
      const _AppendEventCommand(),
      const _TestInput('match/stream', 'value'),
    );
    await projection.started.future;

    expect(eventDatabase.testAppliedEvents, hasLength(1));
    expect(projection.hasCompleted, isFalse);

    projection.release.complete();
    await projection.completed.future;

    expect(projection.values, ['stream:value']);
  });

  test('provides the runtime logger through CommandContext', () async {
    final logger = RecordingLogger();
    final runtime = await createRuntime([], logger: logger);
    Logger? receivedLogger;

    await runtime.executeCommand(
      _LoggerCommand((value) => receivedLogger = value),
      const _TestInput('match/stream', 'value'),
    );

    expect(receivedLogger, same(logger));
  });
}

final class _TestInput implements CommandInput {
  final String streamPath;
  final String value;

  const _TestInput(this.streamPath, this.value);

  @override
  String get kind => 'execute-command-test';

  @override
  Uint8List encode() => Uint8List.fromList(utf8.encode(value));
}

final class _AppendEventCommand implements Command<_TestInput> {
  const _AppendEventCommand();

  @override
  Future<void> handle(_TestInput input, CommandContext ctx) async {
    final stream = ctx.stream<_TestEvent>(input.streamPath);
    await stream.mustNotExist();
    stream.append(_TestEvent(input.value));
  }
}

final class _LoggerCommand implements Command<_TestInput> {
  final void Function(Logger) receiveLogger;

  const _LoggerCommand(this.receiveLogger);

  @override
  Future<void> handle(_TestInput input, CommandContext ctx) async {
    receiveLogger(ctx.logger);
  }
}

final class _TestEvent {
  final String value;

  const _TestEvent(this.value);
}

final class _TestEventCodec implements EventCodec<_TestEvent> {
  const _TestEventCodec();

  @override
  String get kind => 'execute-command-test-event';

  @override
  _TestEvent fromBytes(Uint8List bytes) => _TestEvent(utf8.decode(bytes));

  @override
  Uint8List toBytes(_TestEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));
}

class _RecordingProjection implements Projection<_TestEvent, String> {
  @override
  final String name;
  final String pattern;
  final values = <String>[];
  final applied = Completer<void>();

  _RecordingProjection(this.name, this.pattern);

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard(pattern);

  @override
  final failureHandler = StandardProjectionFailureHandler();

  @override
  Future<void> reset() async {
    values.clear();
  }

  @override
  Future<void> apply(
    String streamParams,
    _TestEvent event,
    EventMetadata metadata,
  ) async {
    values.add('$streamParams:${event.value}');
    applied.complete();
  }

  @override
  void onBatchApplied() {}
}

final class _BlockingProjection extends _RecordingProjection {
  final started = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();

  _BlockingProjection() : super('blocking', 'match/*');

  bool get hasCompleted => completed.isCompleted;

  @override
  Future<void> apply(
    String streamParams,
    _TestEvent event,
    EventMetadata metadata,
  ) async {
    started.complete();
    await release.future;
    values.add('$streamParams:${event.value}');
    completed.complete();
  }
}
