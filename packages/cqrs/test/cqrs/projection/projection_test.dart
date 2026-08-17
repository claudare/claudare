import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

  group('Projection', () {
    test('applies its typed event and stream parameters', () async {
      final projection = _StringProjection();

      expect(
        await ProjectionTester(
          projection,
        ).withEvent('alpha/one', 'event', occuredAt: occurredAt).run(),
        isTrue,
      );
      expect(projection.calls, ['event:one']);
      expect(projection.batchCount, 1);
    });

    test('Object projection manually checks event runtime types', () async {
      final projection = _ObjectProjection();

      expect(
        await (ProjectionTester(projection)
              ..withEvent('anything', 'value', occuredAt: occurredAt)
              ..withEvent('anything', 42, occuredAt: occurredAt))
            .run(),
        isTrue,
      );
      expect(projection.strings, ['value']);
      expect(projection.ints, [42]);
    });

    test('Object projection receives registry-decoded runtime types', () async {
      final projection = _ObjectProjection();
      final eventStore = EventStore(MemoryEventDatabase());
      await eventStore.migrate();
      final runtimeStore = RuntimeStore(MemoryRuntimeDatabase());
      await runtimeStore.initialize();
      final registry =
          EventRegistry()
            ..register(const _StringCodec())
            ..register(const _IntCodec());
      final runner = ProjectionRuntime<Object, String>(
        projection,
        logger: const NoopLogger(),
        runtimeName: 'test',
        runtimeStore: runtimeStore,
        eventRegistry: registry,
      );
      await runner.catchupSelfLoad(eventStore);
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();

      runner.enqueue(
        EventEnvelope(
          streamPath: 'first',
          encodedEvent: registry.encode('decoded'),
          occuredAt: occurredAt,
          localSequence: 1,
        ),
        onDone: firstDone.complete,
      );
      runner.enqueue(
        EventEnvelope(
          streamPath: 'second',
          encodedEvent: registry.encode(7),
          occuredAt: occurredAt,
          localSequence: 2,
        ),
        onDone: secondDone.complete,
      );
      await Future.wait([firstDone.future, secondDone.future]);

      expect(projection.strings, ['decoded']);
      expect(projection.ints, [7]);
    });
  });

  group('projection validation', () {
    test('rejects empty names', () {
      expect(
        () => _runner(_ConfigurableProjection(name: '')),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects non-positive versions', () {
      expect(
        () => _runner(_ConfigurableProjection(version: 0)),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects an empty stream route pattern', () {
      expect(
        () => _runner(
          _ConfigurableProjection(streamRoute: const _EmptyStreamRoute()),
        ),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects duplicate projection names', () {
      expect(
        () => CqrsRuntime(
          dependencies: _dependencies(),
          runtimeName: 'test',
          projections: [
            _ConfigurableProjection(name: 'duplicate'),
            _ConfigurableProjection(name: 'duplicate'),
          ],
        ),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });
  });
}

ProjectionRuntime<String, String> _runner(
  Projection<String, String> projection,
) {
  return ProjectionRuntime(
    projection,
    logger: const NoopLogger(),
    runtimeName: 'test',
    runtimeStore: RuntimeStore(MemoryRuntimeDatabase()),
    eventRegistry: EventRegistry(),
  );
}

CqrsRuntimeDependencies _dependencies() {
  return CqrsRuntimeDependencies(
    eventStore: EventStore(MemoryEventDatabase()),
    runtimeDatabase: MemoryRuntimeDatabase(),
    logger: const NoopLogger(),
    idGenerator: IdGeneratorSequential(),
    timeProvider: FakeTimeProviderStatic.zero(),
  );
}

final class _StringProjection implements Projection<String, String> {
  final calls = <String>[];
  int batchCount = 0;

  @override
  String get name => 'string';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('alpha/*');

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    calls.clear();
    batchCount = 0;
  }

  @override
  Future<void> apply(
    String streamParams,
    String event,
    EventMetadata metadata,
  ) async {
    calls.add('$event:$streamParams');
  }

  @override
  void onBatchApplied() {
    batchCount++;
  }
}

final class _ObjectProjection implements Projection<Object, String> {
  final strings = <String>[];
  final ints = <int>[];

  @override
  String get name => 'object';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => const StreamRouteAll();

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    strings.clear();
    ints.clear();
  }

  @override
  Future<void> apply(
    String streamParams,
    Object event,
    EventMetadata metadata,
  ) async {
    switch (event) {
      case String value:
        strings.add(value);
      case int value:
        ints.add(value);
      default:
        break;
    }
  }

  @override
  void onBatchApplied() {}
}

final class _ConfigurableProjection implements Projection<String, String> {
  @override
  final String name;
  @override
  final int version;
  @override
  final StreamRoute<String> streamRoute;

  _ConfigurableProjection({
    this.name = 'configured',
    this.version = 1,
    this.streamRoute = const StreamRouteAll(),
  });

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {}

  @override
  Future<void> apply(
    String streamParams,
    String event,
    EventMetadata metadata,
  ) async {}

  @override
  void onBatchApplied() {}
}

final class _EmptyStreamRoute extends StreamRoute<String> {
  const _EmptyStreamRoute();

  @override
  String get pattern => '';

  @override
  PatternFilter get filter => const PatternFilter.exact('');

  @override
  String buildPath(String streamParams) => streamParams;

  @override
  String parseParams(String streamPath) => streamPath;
}

final class _StringCodec implements EventCodec<String> {
  const _StringCodec();

  @override
  String get kind => 'test.string';

  @override
  Uint8List toBytes(String event) => Uint8List.fromList(utf8.encode(event));

  @override
  String fromBytes(Uint8List bytes) => utf8.decode(bytes);
}

final class _IntCodec implements EventCodec<int> {
  const _IntCodec();

  @override
  String get kind => 'test.int';

  @override
  Uint8List toBytes(int event) =>
      Uint8List.fromList(utf8.encode(event.toString()));

  @override
  int fromBytes(Uint8List bytes) => int.parse(utf8.decode(bytes));
}
