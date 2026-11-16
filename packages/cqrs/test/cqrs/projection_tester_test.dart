import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'cqrs_runtime/projection_test_support.dart' show AsyncGate;

void main() {
  final occuredAt = DateTime.utc(2026);

  test(
    'retains the loaded model and applies each supplied event once',
    () async {
      final projection = _RecordingProjection();
      final tester = ProjectionTester(projection);
      final first = await tester.run();
      tester.withEvent('account/one', 'opened', occuredAt: occuredAt);
      final second = await tester.run();

      expect(second, same(first));
      expect((await tester.run()).events.single.event, 'opened');
      expect(projection.loads, 1);
    },
  );

  test('passes matching event envelopes in supplied order', () async {
    final model =
        await (ProjectionTester(_RecordingProjection())
              ..withEvent('account/one', 'opened', occuredAt: occuredAt)
              ..withEvent('other/two', 'ignored', occuredAt: occuredAt)
              ..withEvent(
                'account/two',
                'deposit',
                actor: 'b',
                occuredAt: occuredAt,
              ))
            .run();

    expect(model.events.map((e) => e.event), ['opened', 'deposit']);
    expect(model.events.map((e) => e.streamPath), [
      'account/one',
      'account/two',
    ]);
    expect(model.events.map((e) => e.actor), ['a', 'b']);
    expect(model.events.map((e) => e.occuredAt), [occuredAt, occuredAt]);
    expect(model.events.map((e) => e.logPosition), [0, 2]);
  });

  test('passes stream deletion metadata once across runs', () async {
    final tester = ProjectionTester(_RecordingProjection())
      ..withEvent('account/one', 'opened', occuredAt: occuredAt)
      ..withStreamDeleted('account/one', actor: 'b', occuredAt: occuredAt);

    await tester.run();
    final model = await tester.run();

    expect(model.deletions, hasLength(1));
    final deletion = model.deletions.single;
    expect(deletion.streamPath, 'account/one');
    expect(deletion.actor, 'b');
    expect(deletion.occuredAt, occuredAt);
    expect(deletion.logPosition, 1);
  });

  test('ignores stream deletions outside the projection filter', () async {
    final model = await ProjectionTester(_RecordingProjection())
        .withStreamDeleted('other/one', occuredAt: occuredAt)
        .run();

    expect(model.deletions, isEmpty);
  });

  test('waits for an asynchronous deletion handler before returning', () async {
    final gate = AsyncGate();
    addTearDown(gate.release);
    final projection = _RecordingProjection()..beforeDelete = gate.wait;
    var completed = false;
    final result = ProjectionTester(projection)
        .withStreamDeleted('account/one', occuredAt: occuredAt)
        .run()
        .then((model) {
          completed = true;
          return model;
        });

    await gate.entered.future;
    expect(completed, isFalse);
    gate.release();
    expect((await result).deletions.single.streamPath, 'account/one');
  });

  test('waits for loading before applying events', () async {
    final gate = AsyncGate();
    addTearDown(gate.release);
    final projection = _RecordingProjection()..beforeLoad = gate.wait;
    final result = ProjectionTester(projection)
        .withEvent('account/one', 'opened', occuredAt: occuredAt)
        .run();
    await gate.entered.future;
    expect(projection.model.events, isEmpty);
    gate.release();
    expect((await result).events.single.event, 'opened');
  });

  test('waits for each asynchronous handler before returning', () async {
    final gate = AsyncGate();
    addTearDown(gate.release);
    final projection = _RecordingProjection()..beforeApply = gate.wait;
    var completed = false;
    final result = ProjectionTester(projection)
        .withEvent('account/one', 'opened', occuredAt: occuredAt)
        .run()
        .then((model) {
          completed = true;
          return model;
        });
    await gate.entered.future;
    expect(completed, isFalse);
    gate.release();
    expect((await result).events.single.event, 'opened');
  });
}

final class _RecordingModel {
  final events = <EventEnvelope<String>>[];
  final deletions = <StreamDeletion>[];
}

final class _RecordingProjection
    implements Projection<_RecordingModel, String> {
  final model = _RecordingModel();
  int loads = 0;
  Future<void> Function()? beforeLoad;
  Future<void> Function()? beforeApply;
  Future<void> Function()? beforeDelete;

  @override
  String get name => 'recording';

  @override
  LogFilter get filter => const LogFilter.startsWith('account/');

  @override
  Future<ProjectionLoad<_RecordingModel>> load() async {
    loads++;
    await beforeLoad?.call();
    return ProjectionLoad.initial(model);
  }

  @override
  Future<void> apply(
    _RecordingModel model,
    EventEnvelope<String> envelope,
  ) async {
    await beforeApply?.call();
    model.events.add(envelope);
  }

  @override
  Future<void> onStreamDeleted(
    _RecordingModel model,
    StreamDeletion deletion,
  ) async {
    await beforeDelete?.call();
    model.deletions.add(deletion);
  }
}
