import 'dart:typed_data';

import 'package:id_generator/id_generator.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_context.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/command/command_input.dart';
import 'package:core/src/cqrs/command/command_run_result.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/exception/command_execution_exception.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';
import 'package:core/src/cqrs/exception/command_serialization_exception.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/exception/event_store_exception.dart';
import 'package:common/common.dart';
import 'package:time_provider/time_provider.dart';
import 'package:test/test.dart';

void main() {
  test('records exceptions', () async {
    final store = MemoryEventStore();
    final exception = FormatException('invalid command');

    await expectLater(
      _executor(store).executeThrowable(_ThrowingCommand(exception), _Input()),
      throwsA(
        isA<CommandExecutionException>().having(
          (error) => error.cause,
          'cause',
          same(exception),
        ),
      ),
    );

    expect(store.testAllCommands, hasLength(1));
    expect(store.testAllCommands.single.exception, same(exception));
  });

  test('records nacks', () async {
    final store = MemoryEventStore();

    await expectLater(
      _executor(store).executeThrowable(const _NackingCommand(), _Input()),
      throwsA(isA<CommandNack>()),
    );

    expect(store.testAllCommands, hasLength(1));
    expect(store.testAllCommands.single.nackReason, 'not allowed');
  });

  test('does not record concurrency problems', () async {
    final store = MemoryEventStore();

    await expectLater(
      _executor(store).executeThrowable(
        const _ThrowingCommand(ConcurrencyProblem()),
        _Input(),
      ),
      throwsA(isA<ConcurrencyProblem>()),
    );

    expect(store.testAllCommands, isEmpty);
  });

  test('does not record infrastructure failures', () async {
    final store = MemoryEventStore();
    final exception = EventStoreException('read failed');

    await expectLater(
      _executor(store).executeThrowable(_ThrowingCommand(exception), _Input()),
      throwsA(same(exception)),
    );

    expect(store.testAllCommands, isEmpty);
  });

  test('does not catch or record Errors', () async {
    final store = MemoryEventStore();
    final error = StateError('broken invariant');

    await expectLater(
      _executor(store).executeThrowable(_ThrowingCommand(error), _Input()),
      throwsA(same(error)),
    );

    expect(store.testAllCommands, isEmpty);
  });

  test('does not catch or record input serialization Errors', () async {
    final store = MemoryEventStore();
    final error = StateError('input encoding failed');

    await expectLater(
      _executor(
        store,
      ).executeThrowable(const _NackingCommand(), _ErrorEncodingInput(error)),
      throwsA(same(error)),
    );

    expect(store.testAllCommands, isEmpty);
  });

  test('wraps JSON-like input serialization errors', () async {
    final store = MemoryEventStore();

    await expectLater(
      _executor(
        store,
      ).executeThrowable(const _NackingCommand(), _JsonLikeEncodingInput()),
      throwsA(isA<CommandSerializationException>()),
    );

    expect(store.testAllCommands, isEmpty);
  });

  test('returns infrastructure failures through the result wrapper', () async {
    final exception = EventStoreException('read failed');

    final result = await wrapCommandExecutionFuture(
      _executor(
        MemoryEventStore(),
      ).executeThrowable(_ThrowingCommand(exception), _Input()),
    );

    expect(result.exception, same(exception));
  });

  test('propagates command-recording failures', () async {
    final exception = EventStoreException('record failed');

    await expectLater(
      _executor(
        _WriteFailingStore(exception),
      ).executeThrowable(const _NackingCommand(), _Input()),
      throwsA(same(exception)),
    );
  });
}

CommandExecutor _executor(EventStoreCommand store) {
  return CommandExecutor(
    eventStore: store,
    timeProvider: FakeTimeProviderStatic.unixMilliseconds(0),
    idGenerator: IdGeneratorSequential(),
    thisDeviceId: DeviceId(1),
    pageSize: 10,
  );
}

class _Input implements CommandInput {
  @override
  String get kind => 'test';

  @override
  Uint8List encode() => Uint8List(0);
}

class _ErrorEncodingInput extends _Input {
  final StateError error;

  _ErrorEncodingInput(this.error);

  @override
  Uint8List encode() => throw error;
}

class _JsonLikeEncodingInput extends _Input {
  @override
  Uint8List encode() => 1 as dynamic;
}

class _ThrowingCommand implements Command<_Input> {
  final Object failure;

  const _ThrowingCommand(this.failure);

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    throw failure;
  }
}

class _NackingCommand implements Command<_Input> {
  const _NackingCommand();

  @override
  Future<void> handle(_Input input, CommandContext ctx) async {
    ctx.nack('not allowed');
  }
}

class _WriteFailingStore extends MemoryEventStore {
  final EventStoreException exception;

  _WriteFailingStore(this.exception);

  @override
  Future<SaveChangesResult> saveChanges(
    dynamic command,
    dynamic appends,
  ) async {
    throw exception;
  }
}
