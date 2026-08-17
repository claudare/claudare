import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

  group('projection routes', () {
    test('one projection consumes unrelated typed routes', () async {
      final projection = _MultiRouteProjection();
      final tester =
          ProjectionTester(projection)
            ..withEvent('alpha/one', 'first', occuredAt: occurredAt)
            ..withEvent('beta/two', 2, occuredAt: occurredAt);

      expect(await tester.run(), isTrue);
      expect(projection.calls, [
        'alpha:first:one',
        'alpha-overlap:first:one',
        'beta:2:two',
      ]);
      expect(projection.batchCount, 1);
    });

    test(
      'projection runtime decodes and applies unrelated event types',
      () async {
        final projection = _MultiRouteProjection();
        final eventStore = EventStore(MemoryEventDatabase());
        await eventStore.migrate();
        final runtimeStore = RuntimeStore(MemoryRuntimeDatabase());
        await runtimeStore.initialize();
        final registry =
            EventRegistry()
              ..register(const _StringCodec())
              ..register(const _IntCodec());
        final runner = ProjectionRuntime(
          projection,
          logger: const NoopLogger(),
          runtimeName: 'test',
          runtimeVersion: 1,
          runtimeStore: runtimeStore,
          eventRegistry: registry,
        );
        await runner.catchupSelfLoad(eventStore);
        final firstDone = Completer<void>();
        final secondDone = Completer<void>();

        runner.enqueue(
          EventEnvelope(
            streamPath: 'alpha/one',
            encodedEvent: registry.encode('first'),
            occuredAt: occurredAt,
            localSequence: 1,
          ),
          onDone: firstDone.complete,
        );
        runner.enqueue(
          EventEnvelope(
            streamPath: 'beta/two',
            encodedEvent: registry.encode(2),
            occuredAt: occurredAt,
            localSequence: 2,
          ),
          onDone: secondDone.complete,
        );
        await Future.wait([firstDone.future, secondDone.future]);

        expect(projection.calls, [
          'alpha:first:one',
          'alpha-overlap:first:one',
          'beta:2:two',
        ]);
      },
    );

    test('overlapping routes run once each in registration order', () async {
      final projection = _MultiRouteProjection();

      expect(
        await ProjectionTester(
          projection,
        ).withEvent('alpha/one', 'event', occuredAt: occurredAt).run(),
        isTrue,
      );
      expect(projection.calls, ['alpha:event:one', 'alpha-overlap:event:one']);
    });

    test('typed routes ignore unrelated event types', () async {
      final projection = _MultiRouteProjection();

      expect(
        await ProjectionTester(
          projection,
        ).withEvent('alpha/one', 1, occuredAt: occurredAt).run(),
        isTrue,
      );
      expect(projection.calls, isEmpty);
      expect(projection.batchCount, 0);
    });

    test('Object route manually checks event runtime types', () async {
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

    test('Object route receives registry-decoded runtime types', () async {
      final projection = _ObjectProjection();
      final eventStore = EventStore(MemoryEventDatabase());
      await eventStore.migrate();
      final runtimeStore = RuntimeStore(MemoryRuntimeDatabase());
      await runtimeStore.initialize();
      final registry =
          EventRegistry()
            ..register(const _StringCodec())
            ..register(const _IntCodec());
      final runner = ProjectionRuntime(
        projection,
        logger: const NoopLogger(),
        runtimeName: 'test',
        runtimeVersion: 1,
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

    test('rejects projections without routes', () {
      expect(
        () => _runner(_ConfigurableProjection(routes: const [])),
        throwsA(isA<ProjectionConfigurationException>()),
      );
    });

    test('rejects duplicate projection names', () {
      expect(
        () => CqrsRuntime(
          dependencies: _dependencies(),
          runtimeName: 'test',
          runtimeVersion: 1,
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

ProjectionRuntime _runner(Projection projection) {
  return ProjectionRuntime(
    projection,
    logger: const NoopLogger(),
    runtimeName: 'test',
    runtimeVersion: 1,
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

final class _MultiRouteProjection implements Projection {
  final calls = <String>[];
  int batchCount = 0;

  @override
  String get name => 'multi-route';

  @override
  int get version => 1;

  @override
  List<ProjectionRoute> get routes => [
    ProjectionRoute<String, String>(
      streamRoute: StreamRouteWildcard('alpha/*'),
      apply: (params, event, metadata) {
        calls.add('alpha:$event:$params');
      },
    ),
    ProjectionRoute<String, String>(
      streamRoute: StreamRouteWildcard('alpha/*'),
      apply: (params, event, metadata) {
        calls.add('alpha-overlap:$event:$params');
      },
    ),
    ProjectionRoute<int, String>(
      streamRoute: StreamRouteWildcard('beta/*'),
      apply: (params, event, metadata) {
        calls.add('beta:$event:$params');
      },
    ),
  ];

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    calls.clear();
    batchCount = 0;
  }

  @override
  void onBatchApplied() {
    batchCount++;
  }
}

final class _ObjectProjection implements Projection {
  final strings = <String>[];
  final ints = <int>[];

  @override
  String get name => 'object';

  @override
  int get version => 1;

  @override
  List<ProjectionRoute> get routes => [
    ProjectionRoute<Object, String>(
      streamRoute: const StreamRouteAll(),
      apply: (params, event, metadata) {
        switch (event) {
          case String value:
            strings.add(value);
          case int value:
            ints.add(value);
          default:
            break;
        }
      },
    ),
  ];

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    strings.clear();
    ints.clear();
  }

  @override
  void onBatchApplied() {}
}

final class _ConfigurableProjection implements Projection {
  @override
  final String name;
  @override
  final int version;
  @override
  final List<ProjectionRoute> routes;

  _ConfigurableProjection({
    this.name = 'configured',
    this.version = 1,
    List<ProjectionRoute>? routes,
  }) : routes =
           routes ??
           [
             ProjectionRoute<String, String>(
               streamRoute: const StreamRouteAll(),
               apply: (params, event, metadata) {},
             ),
           ];

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {}

  @override
  void onBatchApplied() {}
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
