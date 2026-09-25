import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_context_api.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory_event_store.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test('propagates command exceptions unchanged', () async {
    final database = MemoryEventStore();
    final exception = FormatException('invalid command');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(exception)),
      throwsA(same(exception)),
    );

    expect((await database.getState()).lastCommandLogPosition, isNull);
  });

  test('propagates command errors unchanged', () async {
    final database = MemoryEventStore();
    final error = StateError('broken invariant');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(error)),
      throwsA(same(error)),
    );

    expect((await database.getState()).lastCommandLogPosition, isNull);
  });

  for (final acquireStream in [false, true]) {
    test('skips saving an empty command with locks: $acquireStream', () async {
      final database = MemoryEventStore();
      final store = _RecordingEventStore();

      await _executor(database, eventStore: store).execute(
        _CallbackCommand((context) async {
          if (acquireStream) {
            await context.stream<_Event>('new').mustNotExist();
          }
        }),
      );

      expect(store.savedChanges, isEmpty);
    });
  }

  test('seals the context when an empty command completes', () async {
    final database = MemoryEventStore();
    late CommandContextApi context;

    await _executor(
      database,
    ).execute(_CallbackCommand((value) async => context = value));

    expect(() => context.stream<_Event>('new'), throwsStateError);
  });

  test('persists events in append order across streams', () async {
    final database = MemoryEventStore();

    await _executor(database).execute(
      _CallbackCommand((context) async {
        final first = context.stream<_Event>('first');
        final second = context.stream<_Event>('second');
        await first.mustNotExist();
        await second.mustNotExist();

        first.append(const _Event());
        second.append(const _Event());
        // a bit awkward, but okay
        context.stream<_Event>('first').append(const _Event());
      }),
    );

    final events = await database.getLogEvents(0);
    expect(events.data.map((event) => event.streamPath), [
      'first',
      'second',
      'first',
    ]);
  });
}

CommandExecutor _executor(MemoryEventStore database, {EventStore? eventStore}) {
  final registry = EventRegistry()..add(const _EventCodec());
  return CommandExecutor(
    eventStore: eventStore ?? database,
    streamReader:
        CqrsTestRuntime(eventStore: eventStore ?? database).streamReader,
    timeProvider: FakeTimeProviderStatic.unixMilliseconds(0),
    eventRegistry: registry,
    logger: const NoopLogger(),
  );
}

class _ThrowingCommand implements Command {
  final Object failure;

  const _ThrowingCommand(this.failure);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    final stream = ctx.stream<_Event>('new');
    await stream.mustNotExist();
    stream.append(const _Event());
    throw failure;
  }
}

final class _CallbackCommand implements Command {
  final Future<void> Function(CommandContextApi) _handle;

  const _CallbackCommand(this._handle);

  @override
  Future<void> handle(CommandContextApi ctx) => _handle(ctx);
}

final class _RecordingEventStore extends MemoryEventStore {
  final List<CommandChanges> savedChanges = [];

  @override
  Future<void> saveChanges(CommandChanges changes) {
    savedChanges.add(changes);
    return super.saveChanges(changes);
  }
}

final class _Event {
  const _Event();
}

final class _EventCodec implements EventCodec<_Event> {
  const _EventCodec();

  @override
  String get kind => 'event';

  @override
  _Event fromBytes(Uint8List bytes) => const _Event();

  @override
  Uint8List toBytes(_Event event) => Uint8List(0);
}
