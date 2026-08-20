import 'dart:async';

import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  test('runs the first request immediately', () async {
    var calls = 0;
    final runner = AsyncTrailingRunner(() async {
      calls++;
    });

    final run = runner.run();

    expect(calls, 1);
    await run;
  });

  test('calls during active work share the active future', () async {
    final release = Completer<void>();
    final runner = AsyncTrailingRunner(() => release.future);

    final first = runner.run();
    final second = runner.run();

    expect(identical(first, second), isTrue);
    release.complete();
    await first;
  });

  test('work never overlaps', () async {
    final releases = <Completer<void>>[];
    var active = 0;
    var maximumActive = 0;
    final runner = AsyncTrailingRunner(() async {
      active++;
      maximumActive = active > maximumActive ? active : maximumActive;
      final release = Completer<void>();
      releases.add(release);
      await release.future;
      active--;
    });

    final run = runner.run();
    unawaited(runner.run());
    releases[0].complete();
    await Future<void>.delayed(Duration.zero);

    expect(releases, hasLength(2));
    expect(maximumActive, 1);

    releases[1].complete();
    await run;
  });

  test('a burst during active work coalesces into one trailing run', () async {
    final releases = <Completer<void>>[];
    final runner = AsyncTrailingRunner(() {
      final release = Completer<void>();
      releases.add(release);
      return release.future;
    });

    final run = runner.run();
    unawaited(runner.run());
    unawaited(runner.run());
    unawaited(runner.run());
    releases[0].complete();
    await Future<void>.delayed(Duration.zero);

    expect(releases, hasLength(2));

    releases[1].complete();
    await run;
    expect(releases, hasLength(2));
  });

  test('a request during a trailing run schedules one further run', () async {
    final releases = <Completer<void>>[];
    final runner = AsyncTrailingRunner(() {
      final release = Completer<void>();
      releases.add(release);
      return release.future;
    });

    final run = runner.run();
    unawaited(runner.run());
    releases[0].complete();
    await Future<void>.delayed(Duration.zero);
    unawaited(runner.run());
    releases[1].complete();
    await Future<void>.delayed(Duration.zero);

    expect(releases, hasLength(3));

    releases[2].complete();
    await run;
  });

  test('a request at the completion boundary is not lost', () async {
    final release = Completer<void>();
    var calls = 0;
    final runner = AsyncTrailingRunner(() {
      calls++;
      return calls == 1 ? release.future : Future<void>.value();
    });
    Future<void>? boundaryRun;

    final run = runner.run();
    release.complete();
    scheduleMicrotask(() => boundaryRun = runner.run());

    await run;
    await Future<void>.delayed(Duration.zero);
    await boundaryRun;
    expect(calls, 2);
  });

  // TODO: take a second look at this later.
  test('synchronous reentrant requests are coalesced', () async {
    late final AsyncTrailingRunner runner;
    var calls = 0;
    Future<void>? reentrantRun;
    runner = AsyncTrailingRunner(() async {
      calls++;
      if (calls == 1) reentrantRun = runner.run();
    });

    final run = runner.run();

    expect(identical(run, reentrantRun), isTrue);
    await run;
    expect(calls, 2);
  });

  test('failure propagates unchanged and discards the trailing run', () async {
    final failure = Exception('failed');
    var calls = 0;
    late final AsyncTrailingRunner runner;
    runner = AsyncTrailingRunner(() async {
      calls++;
      if (calls == 1) {
        unawaited(runner.run());
        throw failure;
      }
    });

    await expectLater(runner.run(), throwsA(same(failure)));
    expect(calls, 1);
  });

  test('a later request retries after failure', () async {
    final failure = Exception('failed');
    var calls = 0;
    final runner = AsyncTrailingRunner(() async {
      calls++;
      if (calls == 1) throw failure;
    });

    await expectLater(runner.run(), throwsA(same(failure)));
    await runner.run();

    expect(calls, 2);
  });
}
