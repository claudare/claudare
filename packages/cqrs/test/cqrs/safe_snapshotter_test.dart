import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/safe_snapshotter.dart';
import 'package:test/test.dart';

void main() {
  test(
    'load returns the underlying snapshot and forwards the version',
    () async {
      const snapshot = Snapshot('state', 12);
      final underlying = _Snapshotter(
        load: (version) async {
          expect(version, 3);
          return snapshot;
        },
      );

      expect(
        await SafeSnapshotter(underlying, logger: const NoopLogger()).load(3),
        same(snapshot),
      );
    },
  );

  test('save forwards the version and snapshot', () async {
    const snapshot = Snapshot('state', 12);
    var saved = false;
    final underlying = _Snapshotter(
      save: (version, value) async {
        expect(version, 3);
        expect(value, same(snapshot));
        saved = true;
      },
    );

    await SafeSnapshotter(
      underlying,
      logger: const NoopLogger(),
    ).save(3, snapshot);

    expect(saved, isTrue);
  });

  for (final asynchronous in [false, true]) {
    for (final operation in ['load', 'save']) {
      test(
        '$operation recovers from ${asynchronous ? 'async' : 'sync'} exception',
        () async {
          final failure = Exception('storage unavailable');
          final trace = StackTrace.current;
          final logger = RecordingLogger();
          final underlying = _failingSnapshotter(failure, trace, asynchronous);
          final safe = SafeSnapshotter(underlying, logger: logger);

          if (operation == 'load') {
            expect(await safe.load(1), isNull);
          } else {
            await safe.save(1, const Snapshot('state', 1));
          }

          expect(logger.entries, hasLength(1));
          expect(logger.entries.single.level, LogLevel.error);
          expect(logger.entries.single.error, same(failure));
          expect(logger.entries.single.stackTrace, same(trace));
          expect(logger.entries.single.message, contains(operation));
        },
      );

      test(
        '$operation propagates ${asynchronous ? 'async' : 'sync'} Error',
        () async {
          final failure = StateError('bug');
          final trace = StackTrace.current;
          final logger = RecordingLogger();
          final safe = SafeSnapshotter(
            _failingSnapshotter(failure, trace, asynchronous),
            logger: logger,
          );

          await expectLater(
            operation == 'load'
                ? safe.load(1)
                : safe.save(1, const Snapshot('state', 1)),
            throwsA(same(failure)),
          );
          expect(logger.entries, isEmpty);
        },
      );
    }
  }
}

_Snapshotter _failingSnapshotter(
  Object failure,
  StackTrace trace,
  bool asynchronous,
) {
  Future<T> fail<T>() {
    if (asynchronous) return Future<T>.error(failure, trace);
    Error.throwWithStackTrace(failure, trace);
  }

  return _Snapshotter(load: (_) => fail(), save: (_, _) => fail());
}

final class _Snapshotter implements Snapshotter<String> {
  final Future<Snapshot<String>?> Function(int) _load;
  final Future<void> Function(int, Snapshot<String>) _save;

  _Snapshotter({
    Future<Snapshot<String>?> Function(int)? load,
    Future<void> Function(int, Snapshot<String>)? save,
  }) : _load = load ?? ((_) async => null),
       _save = save ?? ((_, _) async {});

  @override
  Future<Snapshot<String>?> load(int aggregateVersion) =>
      _load(aggregateVersion);

  @override
  Future<void> save(int aggregateVersion, Snapshot<String> snapshot) =>
      _save(aggregateVersion, snapshot);
}
