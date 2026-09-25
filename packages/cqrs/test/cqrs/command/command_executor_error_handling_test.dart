import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test('propagates command exceptions unchanged', () async {
    final database = MemoryEventDatabase();
    final exception = FormatException('invalid command');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(exception), null),
      throwsA(same(exception)),
    );

    expect((await database.getLogCommands(0, 1)), isEmpty);
  });

  test('propagates command errors unchanged', () async {
    final database = MemoryEventDatabase();
    final error = StateError('broken invariant');

    await expectLater(
      _executor(database).execute(_ThrowingCommand(error), null),
      throwsA(same(error)),
    );

    expect((await database.getLogCommands(0, 1)), isEmpty);
  });
}

CommandExecutor _executor(MemoryEventDatabase database) {
  final registry = EventRegistry()..add(const _EventCodec());
  return CommandExecutor(
    eventStore: EventStore(database),
    timeProvider: FakeTimeProviderStatic.unixMilliseconds(0),
    eventRegistry: registry,
    logger: const NoopLogger(),
  );
}

class _ThrowingCommand implements Command<dynamic> {
  final Object failure;

  const _ThrowingCommand(this.failure);

  @override
  Future<void> handle(dynamic input, CommandContext ctx) async {
    throw failure;
  }
}

// class _SuccessfulCommand implements Command<_Input> {
//   const _SuccessfulCommand();
//
//   @override
//   Future<void> handle(_Input input, CommandContext ctx) async {
//     final stream = ctx.stream<_Event>('test');
//     await stream.lockLatest();
//     stream.append(const _Event());
//   }
// }

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
