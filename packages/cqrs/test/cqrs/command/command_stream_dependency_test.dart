import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  late MemoryEventDatabase database;
  late EventStore eventStore;
  late EventRegistry eventRegistry;

  setUp(() async {
    database = MemoryEventDatabase();
    eventStore = EventStore(database, eventFetchPageSize: 2);
    eventRegistry = EventRegistry()..add(const _EventCodec());

    await _seedCommand(
      database,
      commandId: CommandId(1, 1),
      streamPaths: const ['target', 'target'],
    );
    await _seedCommand(
      database,
      commandId: CommandId(2, 1),
      streamPaths: const ['target'],
    );
    await _seedCommand(
      database,
      commandId: CommandId(1, 2),
      dependency: VersionVector({1: 1}),
      streamPaths: const ['target'],
    );
    await _seedCommand(
      database,
      commandId: CommandId(3, 1),
      streamPaths: const ['unrelated'],
    );
  });

  test('mustNotExist applies no dependencies', () async {
    await _execute(eventStore, eventRegistry, (context) async {
      final stream = context.stream<_Event>('new');
      await stream.mustNotExist();
      stream.append(const _Event());
    });

    expect(
      (await database.getLogCommands(0, 10)).last.dependency,
      VersionVector(),
    );
  });

  test('mustExist applies only the first event command', () async {
    await _execute(eventStore, eventRegistry, (context) async {
      final stream = context.stream<_Event>('target');
      await stream.mustExist();
      stream.append(const _Event());
    });

    expect(
      (await database.getLogCommands(0, 10)).last.dependency,
      VersionVector({1: 1}),
    );
  });

  test('lockLatest applies the greatest command sequence per device', () async {
    await _execute(eventStore, eventRegistry, (context) async {
      final stream = context.stream<_Event>('target');
      await stream.lockLatest();
      stream.append(const _Event());
    });

    expect(
      (await database.getLogCommands(0, 10)).last.dependency,
      VersionVector({1: 2, 2: 1}),
    );
  });

  test('scan applies every yielded event command', () async {
    await _execute(eventStore, eventRegistry, (context) async {
      final stream = context.stream<_Event>('target');
      await stream.scan().drain<void>();
      stream.append(const _Event());
    });

    expect(
      (await database.getLogCommands(0, 10)).last.dependency,
      VersionVector({1: 2, 2: 1}),
    );
  });

  test('stopping scan applies and locks only the yielded', () async {
    final executionState = CommandExecutionState(locks: [], events: []);
    final context = CommandContext(
      eventStore: eventStore,
      executionState: executionState,
      eventRegistry: eventRegistry,
      timeProvider: FakeTimeProviderStatic.zero(),
      logger: const NoopLogger(),
    );

    var count = 0;
    await for (final _ in context.stream<_Event>('target').scan()) {
      count++;
      if (count == 2) break;
    }

    expect(context.dependency, VersionVector({1: 1}));
    expect(executionState.locks, hasLength(1));
    expect(executionState.locks.single.originatingStreamVersion, 1);
  });
}

Future<void> _execute(
  EventStore eventStore,
  EventRegistry eventRegistry,
  Future<void> Function(CommandContext context) handle,
) async {
  final executor = CommandExecutor(
    eventStore: eventStore,
    timeProvider: FakeTimeProviderStatic.zero(),
    eventRegistry: eventRegistry,
    logger: const NoopLogger(),
  );
  await executor.execute(_Command(handle), const _Input());
}

Future<void> _seedCommand(
  MemoryEventDatabase database, {
  required CommandId commandId,
  required List<String> streamPaths,
  VersionVector? dependency,
}) {
  return database.appendLog(
    StagedCommand(
      commandId: commandId,
      dependency: dependency ?? VersionVector(),
      encoded: EncodedCommand(kind: 'seed', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      eventCount: streamPaths.length,
    ),
    [
      for (var index = 0; index < streamPaths.length; index++)
        StagedEvent(
          eventId: EventId(commandId.deviceId, commandId.sequence, index),
          streamPath: streamPaths[index],
          encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List(0)),
          occuredAt: _timestamp,
        ),
    ],
  );
}

final class _Input implements CommandInput {
  const _Input();

  @override
  String get kind => 'test';

  @override
  Uint8List encode() => Uint8List(0);
}

final class _Command implements Command<_Input> {
  final Future<void> Function(CommandContext context) _handle;

  const _Command(this._handle);

  @override
  Future<void> handle(_Input input, CommandContext context) => _handle(context);
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
