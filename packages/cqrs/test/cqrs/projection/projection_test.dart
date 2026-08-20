import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

  group('Projection', () {
    test('applies its typed event and stream parameters', () async {
      final projection = _StringProjection();

      await ProjectionTester(
        projection,
      ).withEvent('alpha/one', 'event', occuredAt: occurredAt).run();
      expect(projection.calls, ['event:one']);
      expect(projection.batchCount, 1);
    });

    test('Object projection manually checks event runtime types', () async {
      final projection = _ObjectProjection();

      await (ProjectionTester(projection)
            ..withEvent('anything', 'value', occuredAt: occurredAt)
            ..withEvent('anything', 42, occuredAt: occurredAt))
          .run();
      expect(projection.strings, ['value']);
      expect(projection.ints, [42]);
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
