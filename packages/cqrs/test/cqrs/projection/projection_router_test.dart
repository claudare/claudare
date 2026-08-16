import 'dart:async';

import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern_all.dart';
import 'package:test/test.dart';

import 'package:cqrs/src/cqrs/projection/projection_sink.dart';
import 'package:cqrs/src/cqrs/projection/projection_router.dart';

void main() {
  group('ProjectionRouter', () {
    test('dispatch routes only affected runners', () {
      final r1 = _FakeProjectionRuntime(affected: true);
      final r2 = _FakeProjectionRuntime(affected: false);
      final router = ProjectionRouter([r1, r2]);

      final e = _fakeEvent(sequence: 1);

      router.dispatch([e]);

      expect(r1.enqueued.length, 1);
      expect(r2.enqueued.length, 0);
    });

    test('dispatchAndWait routes only affected runners', () async {
      final r1 = _FakeProjectionRuntime(affected: true);
      final r2 = _FakeProjectionRuntime(affected: false);
      final router = ProjectionRouter([r1, r2]);

      final e = _fakeEvent(sequence: 1);

      await router.dispatchAndWait([e]);

      expect(r1.enqueued.length, 1);
      expect(r2.enqueued.length, 0);
    });

    test('dispatchAndWait waits for all affected enqueue callbacks', () async {
      final r1 = _FakeProjectionRuntime(affected: true, immediateDone: false);
      final r2 = _FakeProjectionRuntime(affected: true, immediateDone: false);
      final router = ProjectionRouter([r1, r2]);

      final e1 = _fakeEvent(sequence: 1);
      final e2 = _fakeEvent(sequence: 2);

      var completed = false;
      final f = router.dispatchAndWait([e1, e2]).then((_) => completed = true);

      // 2 runners x 2 events = 4 pending callbacks
      expect(r1.pendingDoneCount + r2.pendingDoneCount, 4);
      expect(completed, isFalse);

      // Complete 3 -> still pending
      r1.fireOneDone();
      r1.fireOneDone();
      r2.fireOneDone();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      // Complete last -> done
      r2.fireOneDone();
      await f;
      expect(completed, isTrue);
    });

    test('dispatchAndWait completes immediately if nothing affected', () async {
      final r1 = _FakeProjectionRuntime(affected: false);
      final r2 = _FakeProjectionRuntime(affected: false);
      final router = ProjectionRouter([r1, r2]);

      await router.dispatchAndWait([_fakeEvent(sequence: 1)]);
      expect(r1.enqueued, isEmpty);
      expect(r2.enqueued, isEmpty);
    });

    test(
      'dispatchAndWait handles immediate onDone race (sync callbacks)',
      () async {
        final r1 = _FakeProjectionRuntime(affected: true, immediateDone: true);
        final r2 = _FakeProjectionRuntime(affected: true, immediateDone: true);
        final router = ProjectionRouter([r1, r2]);

        await router.dispatchAndWait([
          _fakeEvent(sequence: 1),
          _fakeEvent(sequence: 2),
          _fakeEvent(sequence: 3),
        ]);

        expect(r1.enqueued.length, 3);
        expect(r2.enqueued.length, 3);
      },
    );

    test('dispatchAndWait with empty events completes', () async {
      final r1 = _FakeProjectionRuntime(affected: true);
      final router = ProjectionRouter([r1]);

      await router.dispatchAndWait(const []);
      expect(r1.enqueued, isEmpty);
    });
  });
}

// -------------------- Fakes --------------------

class _FakeProjectionRuntime implements ProjectionSink {
  final bool affected;
  final bool immediateDone;

  final List<EventEnvelope> enqueued = [];
  final List<void Function()> _pendingDone = [];

  _FakeProjectionRuntime({required this.affected, this.immediateDone = true});

  @override
  bool shouldProcess(_, _) => affected;

  @override
  void enqueue(EventEnvelope event, {void Function()? onDone}) {
    enqueued.add(event);
    if (immediateDone) {
      onDone?.call(); // simulate sync completion race
    } else if (onDone != null) {
      _pendingDone.add(onDone); // manual control
    }
  }

  int get pendingDoneCount => _pendingDone.length;

  void fireOneDone() {
    final cb = _pendingDone.removeAt(0);
    cb();
  }
}

EventEnvelope _fakeEvent({required int sequence}) {
  return EventEnvelope(
    streamIdStr: '',
    streamIdData: null,
    streamIdPattern: StreamIdPatternAll(),
    event: null,
    metadata: EventMetadata(
      occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    localSequence: sequence,
  );
}
