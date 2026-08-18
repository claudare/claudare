import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:test/test.dart';

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
            ..add(const _StringCodec())
            ..add(const _IntCodec());
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
