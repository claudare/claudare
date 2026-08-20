import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:cqrs/src/cqrs/exception/command_codec_exception.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test('propagates command exceptions unchanged', () async {
    final database = MemoryEventDatabase();
    final exception = FormatException('invalid command');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(exception), _Input()),
      throwsA(same(exception)),
    );

    expect(database.testAppliedCommands, isEmpty);
  });

  test('propagates command errors unchanged', () async {
    final database = MemoryEventDatabase();
    final error = StateError('broken invariant');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(error), _Input()),
      throwsA(same(error)),
    );

    expect(database.testAppliedCommands, isEmpty);
  });

  test('wraps input encoding exceptions', () async {
    final database = MemoryEventDatabase();
    final exception = FormatException('input encoding failed');

    await expectLater(
      _executor(
        database,
      ).execute(const _SuccessfulCommand(), _ThrowingInput(exception)),
      throwsA(
        isA<CommandCodecException>()
            .having(
              (failure) => failure.direction,
              'direction',
              CommandCodecDirection.encode,
            )
            .having((failure) => failure.kind, 'kind', 'test')
            .having(
              (failure) => failure.message,
              'message',
              'Failed to encode command of kind test',
            )
            .having((failure) => failure.error, 'error', same(exception))
            .having(
              (failure) => failure.toString(),
              'toString',
              'CommandCodecException{kind: test, direction: CommandCodecDirection.encode, message: Failed to encode command of kind test, error: FormatException: input encoding failed}',
            ),
      ),
    );

    expect(database.testAppliedCommands, isEmpty);
  });

  test('wraps input encoding errors', () async {
    final database = MemoryEventDatabase();
    final error = StateError('input encoding failed');

    await expectLater(
      _executor(
        database,
      ).execute(const _SuccessfulCommand(), _ThrowingInput(error)),
      throwsA(
        isA<CommandCodecException>().having(
          (failure) => failure.error,
          'error',
          same(error),
        ),
      ),
    );

    expect(database.testAppliedCommands, isEmpty);
  });
}

CommandExecutor _executor(MemoryEventDatabase database) {
  final registry = EventRegistry()..add(const _EventCodec());
  return CommandExecutor(
    eventStore: EventStore(database),
    timeProvider: FakeTimeProviderStatic.unixMilliseconds(0),
    idGenerator: IdGeneratorSequential(),
    eventRegistry: registry,
    logger: const NoopLogger(),
  );
}

class _Input implements CommandInput {
  @override
  String get kind => 'test';

  @override
  Uint8List encode() => Uint8List(0);
}

class _ThrowingInput extends _Input {
  final Object failure;

  _ThrowingInput(this.failure);

  @override
  Uint8List encode() => throw failure;
}

class _ThrowingCommand implements Command<_Input> {
  final Object failure;

  const _ThrowingCommand(this.failure);

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    throw failure;
  }
}

class _SuccessfulCommand implements Command<_Input> {
  const _SuccessfulCommand();

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    final stream = ctx.stream<_Event>('test');
    await stream.lock();
    stream.append(const _Event());
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
