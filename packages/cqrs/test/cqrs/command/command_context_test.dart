import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  late _ControlledDatabase database;
  late EventStore store;
  late EventRegistry registry;
  late _MutableTimeProvider timeProvider;
  late CommandContext context;

  CommandContext createContext({EventRegistry? eventRegistry}) =>
      CommandContext(
        eventStore: store,
        eventRegistry: eventRegistry ?? registry,
        timeProvider: timeProvider,
        logger: const NoopLogger(),
      );

  setUp(() async {
    database = _ControlledDatabase();
    store = EventStore(database, eventFetchPageSize: 1);
    registry = EventRegistry()..add(const _EventCodec());
    timeProvider = _MutableTimeProvider(_timestamp);
    for (var index = 0; index < 2; index++) {
      await store.saveChanges(
        CommandChanges(
          dependency: VersionVector(),
          occuredAt: _timestamp,
          locks: [
            StreamLock(
              streamPath: 'existing',
              originatingStreamVersion: index == 0 ? null : index - 1,
            ),
          ],
          events: [
            EventAppend(
              streamPath: 'existing',
              encodedEvent: registry.encode(_Event(index)),
              occuredAt: _timestamp,
            ),
          ],
        ),
      );
    }
    context = createContext();
  });

  final acquisitions = [
    (
      name: 'scan',
      path: 'existing',
      run: (CommandStream<_Event> stream) => stream.scan().drain<void>(),
    ),
    (
      name: 'lockLatest',
      path: 'existing',
      run: (CommandStream<_Event> stream) => stream.lockLatest(),
    ),
    (
      name: 'mustExist',
      path: 'existing',
      run: (CommandStream<_Event> stream) => stream.mustExist(),
    ),
    (
      name: 'mustNotExist',
      path: 'new',
      run: (CommandStream<_Event> stream) => stream.mustNotExist(),
    ),
  ];

  for (final acquisition in acquisitions) {
    group(acquisition.name, () {
      test('shares a completed lock between typed handles', () async {
        final first = context.stream<_Event>(acquisition.path);
        final second = context.stream<Object>(acquisition.path);

        await acquisition.run(first);
        first.append(const _Event(2));
        second.append(const _Event(3));

        final changes = context.finish();
        expect(changes.locks.single.streamPath, acquisition.path);
        expect(changes.events, hasLength(2));
      });

      test('rejects another acquisition after completion', () async {
        await acquisition.run(context.stream<_Event>(acquisition.path));

        await expectLater(
          context.stream<_Event>(acquisition.path).lockLatest(),
          throwsStateError,
        );
      });

      test('rejects another acquisition while pending', () async {
        final pause = _pauseReads(database);
        final pending = acquisition.run(
          context.stream<_Event>(acquisition.path),
        );
        await pause.started;

        await expectLater(
          context.stream<_Event>(acquisition.path).lockLatest(),
          throwsStateError,
        );

        pause.resume();
        await pending;
      });

      test('rejects appending while pending', () async {
        final pause = _pauseReads(database);
        final pending = acquisition.run(
          context.stream<_Event>(acquisition.path),
        );
        await pause.started;

        expect(
          () =>
              context.stream<_Event>(acquisition.path).append(const _Event(2)),
          throwsStateError,
        );

        pause.resume();
        await pending;
      });

      test('rejects acquisition after finalization', () async {
        final stream = context.stream<_Event>(acquisition.path);
        context.finish();

        await expectLater(acquisition.run(stream), throwsStateError);
      });

      test('seals pending acquisition without applying later events', () async {
        final pause = _pauseReads(database);
        final pending = acquisition.run(
          context.stream<_Event>(acquisition.path),
        );
        final pendingFailure = expectLater(pending, throwsStateError);
        await pause.started;

        expect(context.finish, throwsStateError);
        pause.resume();
        await pendingFailure;

        expect(context.dependency, VersionVector());
        expect(context.finish, throwsStateError);
      });
    });
  }

  test('rejects appending before acquisition', () {
    final stream = context.stream<_Event>('existing');

    expect(() => stream.append(const _Event(2)), throwsStateError);
  });

  test('rejects appending while a scan is suspended at an event', () async {
    final stream = context.stream<_Event>('existing');
    final iterator = StreamIterator(stream.scan());
    addTearDown(iterator.cancel);
    await iterator.moveNext();

    expect(() => stream.append(const _Event(2)), throwsStateError);
  });

  test('allows appending after cancelling a scan', () async {
    final stream = context.stream<_Event>('existing');
    final iterator = StreamIterator(stream.scan());
    await iterator.moveNext();
    await iterator.cancel();

    stream.append(const _Event(2));

    final changes = context.finish();
    expect(changes.events, hasLength(1));
    expect(changes.locks.single.originatingStreamVersion, 0);
  });

  test('records the yielded prefix when decoding fails', () async {
    final failingRegistry =
        EventRegistry()..add(const _EventCodec(failOnValue: 1));
    final failingContext = createContext(eventRegistry: failingRegistry);

    await expectLater(
      failingContext.stream<_Event>('existing').scan().drain<void>(),
      throwsA(isA<EventCodecException>()),
    );

    final changes = failingContext.finish();
    expect(changes.dependency, VersionVector({0: 1}));
    expect(changes.locks.single.originatingStreamVersion, 0);
  });

  test('lockLatest collects dependencies without decoding', () async {
    final failingRegistry =
        EventRegistry()..add(const _EventCodec(failOnValue: 0));
    final failingContext = createContext(eventRegistry: failingRegistry);

    await failingContext.stream<_Event>('existing').lockLatest();

    expect(failingContext.finish().dependency, VersionVector({0: 2}));
  });

  final failedAcquisitions = [
    (
      name: 'mustExist',
      path: 'missing',
      run: (CommandStream<_Event> stream) => stream.mustExist(),
      error: isA<StreamNotFoundException>(),
    ),
    (
      name: 'mustNotExist',
      path: 'existing',
      run: (CommandStream<_Event> stream) => stream.mustNotExist(),
      error: isA<StreamAlreadyExistsException>(),
    ),
  ];

  for (final acquisition in failedAcquisitions) {
    group('failed ${acquisition.name}', () {
      test('does not authorize append', () async {
        final stream = context.stream<_Event>(acquisition.path);
        await expectLater(acquisition.run(stream), throwsA(acquisition.error));

        expect(() => stream.append(const _Event(2)), throwsStateError);
      });

      test('keeps the path reserved against retry', () async {
        await expectLater(
          acquisition.run(context.stream<_Event>(acquisition.path)),
          throwsA(acquisition.error),
        );

        await expectLater(
          context.stream<_Event>(acquisition.path).lockLatest(),
          throwsStateError,
        );
      });

      test('allows finalizing changes to other streams', () async {
        await expectLater(
          acquisition.run(context.stream<_Event>(acquisition.path)),
          throwsA(acquisition.error),
        );
        final output = context.stream<_Event>('output');
        await output.mustNotExist();
        output.append(const _Event(2));

        final changes = context.finish();
        expect(changes.locks.single.streamPath, 'output');
        expect(changes.isValid(), isTrue);
      });
    });
  }

  test('preserves interleaved append order across streams', () async {
    final first = context.stream<_Event>('existing');
    final second = context.stream<_Event>('new');
    await first.lockLatest();
    await second.mustNotExist();

    first.append(const _Event(2));
    second.append(const _Event(3));
    context.stream<_Event>('existing').append(const _Event(4));

    expect(
      context.finish().events.map(
        (event) => (
          event.streamPath,
          registry.decode<_Event>(event.encodedEvent).value,
        ),
      ),
      [('existing', 2), ('new', 3), ('existing', 4)],
    );
  });

  test('ignores unused stream handles when finalizing', () {
    context.stream<_Event>('existing');

    expect(context.finish().locks, isEmpty);
  });

  test('finalizes an empty command', () {
    expect(context.finish().events, isEmpty);
  });

  test('returns an unmodifiable event list', () async {
    final stream = context.stream<_Event>('existing');
    await stream.lockLatest();
    stream.append(const _Event(2));

    expect(context.finish().events.clear, throwsUnsupportedError);
  });

  test('returns an unmodifiable lock list', () async {
    await context.stream<_Event>('existing').lockLatest();

    expect(context.finish().locks.clear, throwsUnsupportedError);
  });

  test('rejects stream handles after finalization', () {
    context.finish();

    expect(() => context.stream<_Event>('new'), throwsStateError);
  });

  test(
    'rejects appends through a retained handle after finalization',
    () async {
      final stream = context.stream<_Event>('existing');
      await stream.lockLatest();
      context.finish();

      expect(() => stream.append(const _Event(2)), throwsStateError);
    },
  );

  test('rejects a scan first listened to after finalization', () async {
    final scan = context.stream<_Event>('existing').scan();
    context.finish();

    await expectLater(scan.drain<void>(), throwsStateError);
  });

  test('rejects repeated finalization', () {
    context.finish();

    expect(context.finish, throwsStateError);
  });

  test('captures the command timestamp at context creation', () async {
    timeProvider.value = _timestamp.add(const Duration(seconds: 1));
    await context.stream<_Event>('existing').lockLatest();
    timeProvider.value = _timestamp.add(const Duration(seconds: 2));

    expect(context.finish().occuredAt, _timestamp);
  });

  test('captures each event timestamp at append', () async {
    final stream = context.stream<_Event>('existing');
    await stream.lockLatest();
    final firstTime = _timestamp.add(const Duration(seconds: 1));
    final secondTime = _timestamp.add(const Duration(seconds: 2));

    timeProvider.value = firstTime;
    stream.append(const _Event(2));
    timeProvider.value = secondTime;
    stream.append(const _Event(3));

    expect(context.finish().events.map((event) => event.occuredAt), [
      firstTime,
      secondTime,
    ]);
  });
}

({Future<void> started, void Function() resume}) _pauseReads(
  _ControlledDatabase database,
) {
  final started = Completer<void>();
  final released = Completer<void>();
  database.beforeRead = () async {
    if (!started.isCompleted) started.complete();
    await released.future;
  };
  void resume() {
    database.beforeRead = null;
    if (!released.isCompleted) released.complete();
  }

  addTearDown(resume);
  return (started: started.future, resume: resume);
}

final class _ControlledDatabase extends MemoryEventDatabase {
  Future<void> Function()? beforeRead;

  @override
  Future<int?> getStreamVersion(String streamPath) async {
    await beforeRead?.call();
    return super.getStreamVersion(streamPath);
  }

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
    int count,
  ) async {
    await beforeRead?.call();
    return super.getStreamEvents(streamPath, fromVersion, count);
  }
}

final class _MutableTimeProvider implements TimeProvider {
  DateTime value;

  _MutableTimeProvider(this.value);

  @override
  DateTime now() => value;
}

final class _Event {
  final int value;

  const _Event(this.value);
}

final class _EventCodec implements EventCodec<_Event> {
  final int? failOnValue;

  const _EventCodec({this.failOnValue});

  @override
  String get kind => 'event';

  @override
  _Event fromBytes(Uint8List bytes) {
    if (bytes.single == failOnValue) {
      throw const FormatException('cannot decode event');
    }
    return _Event(bytes.single);
  }

  @override
  Uint8List toBytes(_Event event) => Uint8List.fromList([event.value]);
}
