import 'dart:async';

import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  test('starts the first callback immediately', () async {
    var calls = 0;
    final runner = AsyncThrottledRunner(() async {
      calls++;
    }, delay: Duration.zero);

    final run = runner.run();
    expect(calls, 1);
    await run;
    expect(runner.activeRun, isNull);
  });

  test('waits for the configured throttle interval', () {
    return _withTimers((timers) async {
      const delay = Duration(milliseconds: 35);
      var calls = 0;
      final runner = AsyncThrottledRunner(() async {
        calls++;
      }, delay: delay);
      var completed = false;

      final run = runner.run();
      final completion = run.then((_) => completed = true);
      await _flush();

      expect(calls, 1);
      expect(completed, isFalse);
      expect(runner.activeRun, same(run));
      expect(timers.single.duration, delay);

      timers.single.fire();
      await completion;

      expect(calls, 1);
      expect(completed, isTrue);
      expect(runner.activeRun, isNull);
    });
  });

  test('requests during the interval share a future and coalesce', () {
    return _withTimers((timers) async {
      var calls = 0;
      final runner = AsyncThrottledRunner(() async {
        calls++;
      });

      final first = runner.run();
      await _flush();
      expect(runner.run(), same(first));
      expect(runner.run(), same(first));
      expect(runner.run(), same(first));
      expect(calls, 1);

      timers[0].fire();
      await _flush();
      expect(calls, 2);
      expect(timers, hasLength(2));

      timers[1].fire();
      await first;
      expect(calls, 2);
    });
  });

  test('slow callbacks never overlap or add another delay after finishing', () {
    return _withTimers((timers) async {
      final releases = <Completer<void>>[];
      var active = 0;
      var maximumActive = 0;
      final runner = AsyncThrottledRunner(() async {
        active++;
        maximumActive = active > maximumActive ? active : maximumActive;
        final release = Completer<void>();
        releases.add(release);
        await release.future;
        active--;
      });

      final run = runner.run();
      expect(runner.run(), same(run));
      timers[0].fire();
      await _flush();
      expect(releases, hasLength(1));
      expect(active, 1);

      releases[0].complete();
      await _flush();
      expect(releases, hasLength(2));
      expect(maximumActive, 1);

      timers[1].fire();
      releases[1].complete();
      await run;
      expect(active, 0);
      expect(runner.activeRun, isNull);
    });
  });

  test('requests during a trailing run schedule one further run', () {
    return _withTimers((timers) async {
      var calls = 0;
      final runner = AsyncThrottledRunner(() async {
        calls++;
      });

      final run = runner.run();
      expect(runner.run(), same(run));
      timers[0].fire();
      await _flush();
      expect(calls, 2);
      expect(runner.run(), same(run));
      expect(runner.run(), same(run));
      timers[1].fire();
      await _flush();
      expect(calls, 3);

      timers[2].fire();
      await run;
      expect(calls, 3);
    });
  });

  test('a new request after idle starts immediately', () {
    return _withTimers((timers) async {
      var calls = 0;
      final runner = AsyncThrottledRunner(() async {
        calls++;
      });

      final first = runner.run();
      timers[0].fire();
      await first;

      final second = runner.run();
      expect(second, isNot(same(first)));
      expect(calls, 2);

      timers[1].fire();
      await second;
    });
  });

  test('synchronous reentrant requests share the active future', () {
    return _withTimers((timers) async {
      late final AsyncThrottledRunner runner;
      Future<void>? reentrant;
      var calls = 0;
      runner = AsyncThrottledRunner(() async {
        calls++;
        if (calls == 1) reentrant = runner.run();
      });

      final run = runner.run();
      expect(reentrant, same(run));
      timers[0].fire();
      await _flush();
      expect(calls, 2);

      timers[1].fire();
      await run;
    });
  });

  for (final synchronous in [false, true]) {
    test(
      '${synchronous ? 'synchronous' : 'async'} failures discard trailing work',
      () {
        return _withTimers((timers) async {
          final failure = Exception('failed');
          final stackTrace = StackTrace.current;
          var calls = 0;
          final runner = AsyncThrottledRunner(() {
            calls++;
            if (synchronous) Error.throwWithStackTrace(failure, stackTrace);
            return Future<void>.error(failure, stackTrace);
          });

          final run = runner.run();
          expect(runner.run(), same(run));
          final failed = expectLater(run, throwsA(same(failure)));
          StackTrace? receivedStack;
          final trace = run.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              receivedStack = stack;
            },
          );
          await _flush();
          expect(runner.activeRun, same(run));

          timers.single.fire();
          await failed;
          await trace;
          expect(receivedStack.toString(), stackTrace.toString());
          expect(calls, 1);
          expect(runner.activeRun, isNull);
        });
      },
    );
  }

  test('a later request can retry after failure', () {
    return _withTimers((timers) async {
      var calls = 0;
      final runner = AsyncThrottledRunner(() async {
        calls++;
        if (calls == 1) throw Exception('failed');
      });

      final first = runner.run();
      final failed = expectLater(first, throwsException);
      timers[0].fire();
      await failed;

      final second = runner.run();
      expect(calls, 2);
      timers[1].fire();
      await second;
    });
  });

  test('rejects negative intervals', () {
    expect(
      () => AsyncThrottledRunner(
        () async {},
        delay: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _withTimers(
  Future<void> Function(List<_ControlledTimer> timers) body,
) {
  final timers = <_ControlledTimer>[];
  return runZoned(
    () => body(timers),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == Duration.zero) {
          return parent.createTimer(zone, duration, callback);
        }
        final timer = _ControlledTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
}

class _ControlledTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  _ControlledTimer(this.duration, this._callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}
