import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/event_pump.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/projection_page_adapter.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:test/test.dart';

// Uses real registry and runtime progress with a controlled event reader.
// Completers pause reads or handlers to make concurrency races deterministic.
void main() {
  late _PumpFixture fixture;

  setUp(() async {
    fixture = await _PumpFixture.create();
  });

  group('routing and page processing', () {
    test('starts after the minimum projection position', () async {
      final first = _TestProjection<String>(name: 'first');
      final second = _TestProjection<String>(name: 'second');
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(2, 'two'),
        fixture.stringEvent(3, 'three'),
      ]);
      final pump = fixture.pump(source, [
        await fixture.adapter(first),
        await fixture.adapter(second, position: 2),
      ]);

      await pump.pump();

      expect(source.readerStarts, [0]);
      expect(first.events, ['one', 'two', 'three']);
      expect(second.events, ['three']);
      expect(await fixture.position('first'), 3);
      expect(await fixture.position('second'), 3);
    });

    test('advances an unmatched page without a batch callback', () async {
      final projection = _TestProjection<String>(
        name: 'filtered',
        streamRoute: StreamRouteWildcard('match/*'),
      );
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one', path: 'other/one'),
        fixture.stringEvent(2, 'two', path: 'other/two'),
      ]);

      await fixture.pump(source, [await fixture.adapter(projection)]).pump();

      expect(projection.events, isEmpty);
      expect(projection.batchCount, 0);
      expect(await fixture.position('filtered'), 2);
    });

    test('Object projection receives unrelated decoded types', () async {
      final projection = _TestProjection<Object>(name: 'object');
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.intEvent(2, 2),
      ]);

      await fixture.pump(source, [await fixture.adapter(projection)]).pump();

      expect(projection.events, ['one', 2]);
    });

    test('validates matched decoded objects against the event type', () async {
      final projection = _TestProjection<String>(name: 'typed');
      final source = _ReaderSource([fixture.intEvent(1, 1)]);
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      await expectLater(pump.pump(), throwsA(isA<EventCodecException>()));

      expect(await fixture.rawPosition('typed'), isA<ProjectionInconsistent>());
    });

    test('routes one decoded event to multiple projections', () async {
      final first = _TestProjection<String>(name: 'first');
      final second = _TestProjection<String>(name: 'second');
      final source = _ReaderSource([fixture.stringEvent(1, 'shared')]);

      await fixture.pump(source, [
        await fixture.adapter(first),
        await fixture.adapter(second),
      ]).pump();

      expect(first.events, ['shared']);
      expect(second.events, ['shared']);
    });

    test('decodes each durable event once', () async {
      final first = _TestProjection<String>(name: 'first');
      final second = _TestProjection<String>(name: 'second');
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(2, 'two'),
      ]);

      await fixture.pump(source, [
        await fixture.adapter(first),
        await fixture.adapter(second),
      ]).pump();

      expect(fixture.stringCodec.decodeCount, 2);
    });
  });

  group('local sequence validation', () {
    final invalidSequenceCases = [
      (
        description: 'a gap at the start',
        start: 0,
        sequences: [2],
        expected: 1,
        found: 2,
      ),
      (
        description: 'a gap inside a page',
        start: 0,
        sequences: [1, 3],
        expected: 2,
        found: 3,
      ),
      (
        description: 'a duplicate sequence',
        start: 0,
        sequences: [1, 1],
        expected: 2,
        found: 1,
      ),
      (
        description: 'a sequence regression',
        start: 0,
        sequences: [1, 2, 1],
        expected: 3,
        found: 1,
      ),
      (
        description: 'a gap after a nonzero position',
        start: 2,
        sequences: [4],
        expected: 3,
        found: 4,
      ),
    ];

    for (final testCase in invalidSequenceCases) {
      test('rejects ${testCase.description}', () async {
        final projection = _TestProjection<String>(name: 'sequence');
        final source = _ReaderSource([
          for (final sequence in testCase.sequences)
            fixture.stringEvent(sequence, 'event-$sequence'),
        ]);
        final pump = fixture.pump(source, [
          await fixture.adapter(projection, position: testCase.start),
        ]);

        final failure = await _captureFailure(pump.pump());

        expect(
          failure,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Expected local sequence ${testCase.expected}, but found '
                '${testCase.found}',
          ),
        );
        expect(await _captureFailure(pump.pump()), same(failure));
        expect(await fixture.position('sequence'), testCase.start);
        expect(projection.events, isEmpty);
        expect(fixture.stringCodec.decodeCount, 0);
        expect(source.readCount, 1);
      });
    }

    test('rejects a gap across page boundaries', () async {
      final projection = _TestProjection<String>(name: 'page-sequence');
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(3, 'three'),
        fixture.stringEvent(4, 'four'),
      ], pageSize: 1);
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      final failure = await _captureFailure(pump.pump());

      expect(
        failure,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Expected local sequence 2, but found 3',
        ),
      );
      expect(await fixture.position('page-sequence'), 1);
      expect(projection.events, ['one']);
      expect(projection.batchCount, 1);
      expect(fixture.stringCodec.decodeCount, 1);
      expect(source.readCount, 2);
    });
  });

  group('concurrency and wakeups', () {
    test('processes projections concurrently', () async {
      final release = Completer<void>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final first = _TestProjection<String>(
        name: 'first',
        onApply: (_, _, _) async {
          firstStarted.complete();
          await release.future;
        },
      );
      final second = _TestProjection<String>(
        name: 'second',
        onApply: (_, _, _) async {
          secondStarted.complete();
          await release.future;
        },
      );
      final pump = fixture.pump(
        _ReaderSource([fixture.stringEvent(1, 'event')]),
        [await fixture.adapter(first), await fixture.adapter(second)],
      );

      final pumping = pump.pump();
      await Future.wait([firstStarted.future, secondStarted.future]);
      release.complete();
      await pumping;
    });

    test('applies calls within one projection sequentially', () async {
      final releaseFirst = Completer<void>();
      final firstStarted = Completer<void>();
      var activeCalls = 0;
      var maxActiveCalls = 0;
      var callCount = 0;
      final projection = _TestProjection<String>(
        name: 'sequential',
        onApply: (_, _, _) async {
          callCount++;
          activeCalls++;
          maxActiveCalls =
              activeCalls > maxActiveCalls ? activeCalls : maxActiveCalls;
          if (callCount == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          activeCalls--;
        },
      );
      final pump = fixture.pump(
        _ReaderSource([
          fixture.stringEvent(1, 'one'),
          fixture.stringEvent(2, 'two'),
        ]),
        [await fixture.adapter(projection)],
      );

      final pumping = pump.pump();
      await firstStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 1);
      releaseFirst.complete();
      await pumping;

      expect(callCount, 2);
      expect(maxActiveCalls, 1);
    });

    test('settles the page barrier before reading the next page', () async {
      final releaseFirst = Completer<void>();
      final firstStarted = Completer<void>();
      var callCount = 0;
      final projection = _TestProjection<String>(
        name: 'barrier',
        onApply: (_, _, _) async {
          callCount++;
          if (callCount == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
        },
      );
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(2, 'two'),
      ], pageSize: 1);
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      final pumping = pump.pump();
      await firstStarted.future;
      expect(source.readCount, 1);
      releaseFirst.complete();
      await pumping;

      expect(source.readCount, 3);
      expect(source.maxReadsInFlight, 1);
    });

    test('coalesces concurrent calls and requests another scan', () async {
      final readStarted = Completer<void>();
      final releaseRead = Completer<void>();
      final source = _ReaderSource(
        const [],
        onRead: (read, _) async {
          if (read == 1) {
            readStarted.complete();
            await releaseRead.future;
          }
        },
      );
      final projection = _TestProjection<String>(name: 'coalesced');
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      final first = pump.pump();
      await readStarted.future;
      final second = pump.pump();
      final third = pump.pump();
      expect(second, same(first));
      expect(third, same(first));
      releaseRead.complete();
      await Future.wait([first, second, third]);

      expect(source.readerStarts, [0, 0]);
    });

    test(
      'does not strand events added during active page processing',
      () async {
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final projection = _TestProjection<String>(
          name: 'active-add',
          onApply: (_, event, _) async {
            if (event == 'one') {
              firstStarted.complete();
              await releaseFirst.future;
            }
          },
        );
        final source = _ReaderSource([fixture.stringEvent(1, 'one')]);
        final pump = fixture.pump(source, [await fixture.adapter(projection)]);

        final first = pump.pump();
        await firstStarted.future;
        source.events.add(fixture.stringEvent(2, 'two'));
        final joined = pump.pump();
        releaseFirst.complete();
        await Future.wait([first, joined]);

        expect(projection.events, ['one', 'two']);
        expect(source.readerStarts, [0, 2]);
      },
    );

    test('does not strand an event added at the empty-page boundary', () async {
      final emptyReadStarted = Completer<void>();
      final releaseEmptyRead = Completer<void>();
      final source = _ReaderSource(
        const [],
        onRead: (read, page) async {
          if (read == 1 && page.isEmpty) {
            emptyReadStarted.complete();
            await releaseEmptyRead.future;
          }
        },
      );
      final projection = _TestProjection<String>(name: 'empty-boundary');
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      final first = pump.pump();
      await emptyReadStarted.future;
      source.events.add(fixture.stringEvent(1, 'late'));
      final joined = pump.pump();
      releaseEmptyRead.complete();
      await Future.wait([first, joined]);

      expect(projection.events, ['late']);
      expect(source.readerStarts, [0, 0]);
    });
  });

  group('callbacks and terminal failures', () {
    test('calls back once per matched page after progress commits', () async {
      final observedPositions = <Future<int>>[];
      late _TestProjection<String> projection;
      projection = _TestProjection<String>(
        name: 'callback',
        onBatchApplied: () {
          observedPositions.add(
            fixture.database
                .getProjectionState(projection.name)
                .then((state) => state!.scannedThroughLocalSequence!),
          );
        },
      );
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(2, 'two'),
        fixture.stringEvent(3, 'three'),
      ], pageSize: 2);

      await fixture.pump(source, [await fixture.adapter(projection)]).pump();

      expect(projection.batchCount, 2);
      expect(await Future.wait(observedPositions), [2, 3]);
    });

    test('codec failure is terminal and leaves progress unchanged', () async {
      final projection = _TestProjection<String>(name: 'codec-failure');
      final source = _ReaderSource([
        LocalEvent(
          streamPath: 'all',
          encodedEvent: EncodedEvent(kind: 'missing', bytes: Uint8List(0)),
          occuredAt: _occurredAt,
          localSequence: 1,
        ),
      ]);
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      final firstFailure = await _captureFailure(pump.pump());
      final laterFailure = await _captureFailure(pump.pump());

      expect(firstFailure, isA<EventCodecException>());
      expect(laterFailure, same(firstFailure));
      expect(await fixture.position('codec-failure'), 0);
      expect(source.readCount, 1);
    });

    test(
      'projection Error is terminal and leaves progress inconsistent',
      () async {
        final failure = StateError('projection failed');
        final projection = _TestProjection<String>(
          name: 'projection-failure',
          onApply: (_, _, _) async => throw failure,
        );
        final source = _ReaderSource([fixture.stringEvent(1, 'event')]);
        final pump = fixture.pump(source, [await fixture.adapter(projection)]);

        final activeFailure = await _captureFailureWithStack(pump.pump());
        final laterFailure = await _captureFailureWithStack(pump.pump());

        expect(activeFailure.error, same(failure));
        expect(laterFailure.error, same(failure));
        expect(
          laterFailure.stackTrace.toString(),
          activeFailure.stackTrace.toString(),
        );
        expect(
          await fixture.rawPosition('projection-failure'),
          isA<ProjectionInconsistent>(),
        );
      },
    );

    test('callback failure is terminal after progress commits', () async {
      final failure = StateError('callback failed');
      final projection = _TestProjection<String>(
        name: 'callback-failure',
        onBatchApplied: () => throw failure,
      );
      final pump = fixture.pump(
        _ReaderSource([fixture.stringEvent(1, 'event')]),
        [await fixture.adapter(projection)],
      );

      expect(await _captureFailure(pump.pump()), same(failure));
      expect(await fixture.position('callback-failure'), 1);
      expect(await _captureFailure(pump.pump()), same(failure));
    });

    test('waits for every started projection after one fails', () async {
      final failure = StateError('first failed');
      final otherStarted = Completer<void>();
      final releaseOther = Completer<void>();
      final failing = _TestProjection<String>(
        name: 'failing',
        onApply: (_, _, _) async => throw failure,
      );
      final successful = _TestProjection<String>(
        name: 'successful',
        onApply: (_, _, _) async {
          otherStarted.complete();
          await releaseOther.future;
        },
      );
      final pump = fixture.pump(
        _ReaderSource([fixture.stringEvent(1, 'event')]),
        [await fixture.adapter(failing), await fixture.adapter(successful)],
      );

      final observed = pump.pump().then<Object?>(
        (_) => null,
        onError: (Object error, StackTrace _) => error,
      );
      await otherStarted.future;
      var settled = false;
      unawaited(observed.then((_) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      releaseOther.complete();

      expect(await observed, same(failure));
      expect(await fixture.position('successful'), 1);
    });

    test('does not read a later page after failure', () async {
      final failure = StateError('stop');
      final projection = _TestProjection<String>(
        name: 'stop',
        onApply: (_, _, _) async => throw failure,
      );
      final source = _ReaderSource([
        fixture.stringEvent(1, 'one'),
        fixture.stringEvent(2, 'two'),
      ], pageSize: 1);
      final pump = fixture.pump(source, [await fixture.adapter(projection)]);

      expect(await _captureFailure(pump.pump()), same(failure));
      expect(source.readCount, 1);
    });
  });

  group('empty projections', () {
    test('does not create a reader for an empty projection list', () async {
      final source = _ReaderSource([fixture.stringEvent(1, 'event')]);

      await fixture.pump(source, const []).pump();

      expect(source.readerStarts, isEmpty);
      expect(source.readCount, 0);
    });
  });
}

final _occurredAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

Future<Object> _captureFailure(Future<void> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  fail('Expected the future to fail');
}

Future<({Object error, StackTrace stackTrace})> _captureFailureWithStack(
  Future<void> future,
) async {
  try {
    await future;
  } catch (error, stackTrace) {
    return (error: error, stackTrace: stackTrace);
  }
  fail('Expected the future to fail');
}

final class _PumpFixture {
  final MemoryRuntimeDatabase database;
  final RuntimeStore runtimeStore;
  final EventRegistry registry;
  final _StringCodec stringCodec;

  _PumpFixture._({
    required this.database,
    required this.runtimeStore,
    required this.registry,
    required this.stringCodec,
  });

  static Future<_PumpFixture> create() async {
    final database = MemoryRuntimeDatabase();
    final runtimeStore = RuntimeStore(database);
    await runtimeStore.initialize();
    final stringCodec = _StringCodec();
    final registry =
        EventRegistry()
          ..add(stringCodec)
          ..add(const _IntCodec());
    return _PumpFixture._(
      database: database,
      runtimeStore: runtimeStore,
      registry: registry,
      stringCodec: stringCodec,
    );
  }

  LocalEvent stringEvent(int sequence, String value, {String path = 'all'}) =>
      _event(sequence, path, registry.encode(value));

  LocalEvent intEvent(int sequence, int value, {String path = 'all'}) =>
      _event(sequence, path, registry.encode(value));

  LocalEvent _event(int sequence, String path, EncodedEvent encoded) =>
      LocalEvent(
        streamPath: path,
        encodedEvent: encoded,
        occuredAt: _occurredAt,
        localSequence: sequence,
      );

  Future<ProjectionPageAdapter<TEvent, String>> adapter<TEvent extends Object>(
    _TestProjection<TEvent> projection, {
    int position = 0,
  }) async {
    await runtimeStore.resetProjection(projection.name, 1, () async {});
    if (position > 0) {
      await runtimeStore.advanceProjection(
        projection.name,
        0,
        position,
        () async {},
      );
    }
    return ProjectionPageAdapter(
      projection: projection,
      position: position,
      runtimeStore: runtimeStore,
    );
  }

  EventPump pump(
    _ReaderSource source,
    List<PreparedProjectionPageAdapter> projections,
  ) => EventPump(
    createReader: source.createReader,
    eventRegistry: registry,
    projections: projections,
  );

  Future<ProjectionPosition> rawPosition(String name) =>
      runtimeStore.getProjectionPosition(name);

  Future<int> position(String name) async =>
      (await rawPosition(name) as ProjectionAtSequence)
          .scannedThroughLocalSequence;
}

final class _ReaderSource {
  final List<LocalEvent> events;
  final int pageSize;
  final Future<void> Function(int read, List<LocalEvent> page)? onRead;
  final List<int> readerStarts = [];
  int readCount = 0;
  int readsInFlight = 0;
  int maxReadsInFlight = 0;

  _ReaderSource(Iterable<LocalEvent> events, {this.pageSize = 10, this.onRead})
    : events = events.toList();

  PaginatedReader<LocalEvent> createReader(int cursor) {
    readerStarts.add(cursor);
    return PaginatedReader((cursor) async {
      readCount++;
      readsInFlight++;
      maxReadsInFlight =
          readsInFlight > maxReadsInFlight ? readsInFlight : maxReadsInFlight;
      final page =
          events
              .where((event) => event.localSequence > cursor)
              .take(pageSize)
              .toList();
      try {
        await onRead?.call(readCount, page);
        return PaginatedResult(
          data: page,
          next: page.isEmpty ? null : page.last.localSequence,
        );
      } finally {
        readsInFlight--;
      }
    }, initialCursor: cursor);
  }
}

final class _TestProjection<TEvent extends Object>
    implements Projection<TEvent, String> {
  @override
  final String name;
  @override
  final StreamRoute<String> streamRoute;
  final Future<void> Function(String, TEvent, EventMetadata)? onApply;
  final void Function()? _onBatchApplied;
  final List<TEvent> events = [];
  int batchCount = 0;

  _TestProjection({
    required this.name,
    this.streamRoute = const StreamRouteAll(),
    this.onApply,
    void Function()? onBatchApplied,
  }) : _onBatchApplied = onBatchApplied;

  @override
  int get version => 1;

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    events.clear();
    batchCount = 0;
  }

  @override
  Future<void> apply(
    String streamParams,
    TEvent event,
    EventMetadata metadata,
  ) async {
    await onApply?.call(streamParams, event, metadata);
    events.add(event);
  }

  @override
  void onBatchApplied() {
    batchCount++;
    _onBatchApplied?.call();
  }
}

final class _StringCodec implements EventCodec<String> {
  int decodeCount = 0;

  @override
  String get kind => 'string';

  @override
  String fromBytes(Uint8List bytes) {
    decodeCount++;
    return utf8.decode(bytes);
  }

  @override
  Uint8List toBytes(String event) => Uint8List.fromList(utf8.encode(event));
}

final class _IntCodec implements EventCodec<int> {
  const _IntCodec();

  @override
  String get kind => 'int';

  @override
  int fromBytes(Uint8List bytes) => int.parse(utf8.decode(bytes));

  @override
  Uint8List toBytes(int event) =>
      Uint8List.fromList(utf8.encode(event.toString()));
}
