import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} next command IDs', () {
      late EventStore store;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      test('returns no IDs for an empty store', () async {
        expect(await store.getNextCommandIds(CommandDependency(), 3), isEmpty);
      });

      for (final count in [0, -1]) {
        test('rejects count $count', () async {
          await expectLater(
            store.getNextCommandIds(CommandDependency(), count),
            throwsArgumentError,
          );
        });
      }

      test('preserves command log order across interleaved actors', () async {
        final commands = await _seed(store);
        expect(
          await store.getNextCommandIds(CommandDependency(), 10),
          commands.map((command) => command.commandId).toList(),
        );
      });

      test('returns no IDs when all commands are covered', () async {
        await _seed(store);
        expect(
          await store.getNextCommandIds((await store.getState()).logVersion, 3),
          isEmpty,
        );
      });

      for (final values in [
        {'z': 2},
        {'z': 2, 'unknown': 5},
        {'z': 20},
      ]) {
        test('filters by each actor with vector $values', () async {
          await _seed(store);
          expect(await store.getNextCommandIds(CommandDependency(values), 10), [
            const CommandId('a', 1),
            const CommandId('a', 2),
          ]);
        });
      }

      test('limits the result after filtering covered commands', () async {
        await _seed(store);
        expect(await store.getNextCommandIds(CommandDependency({'z': 1}), 2), [
          const CommandId('a', 1),
          const CommandId('z', 2),
        ]);
      });

      test('scans past batches containing only covered commands', () async {
        for (var sequence = 1; sequence <= 260; sequence++) {
          expect(await store.addStoredCommand(_command('z', sequence)), isTrue);
        }
        expect(await store.addStoredCommand(_command('a', 1)), isTrue);
        expect(
          await store.getNextCommandIds(CommandDependency({'z': 260}), 1),
          [const CommandId('a', 1)],
        );
      });

      test('continues collecting matches across batch boundaries', () async {
        await _seed(store);
        expect(await store.addStoredCommand(_command('z', 3)), isTrue);
        expect(await store.addStoredCommand(_command('z', 4)), isTrue);
        expect(await store.addStoredCommand(_command('a', 3)), isTrue);
        expect(await store.getNextCommandIds(CommandDependency({'z': 4}), 3), [
          const CommandId('a', 1),
          const CommandId('a', 2),
          const CommandId('a', 3),
        ]);
      });

      test('returns one ID for a command containing multiple events', () async {
        expect(
          await store.addStoredCommand(_command('z', 1, eventCount: 3)),
          isTrue,
        );
        expect(await store.getNextCommandIds(CommandDependency(), 10), [
          const CommandId('z', 1),
        ]);
      });

      for (final count in [1, 2, 3]) {
        test('advances through all commands with page size $count', () async {
          final commands = await _seed(store);
          var dependency = CommandDependency();
          final received = <CommandId>[];
          for (var page = 0; page <= commands.length; page++) {
            final ids = await store.getNextCommandIds(dependency, count);
            if (ids.isEmpty) break;
            for (final id in ids) {
              dependency = dependency.advance(id);
              received.add(id);
            }
          }
          expect(
            received,
            commands.map((command) => command.commandId).toList(),
          );
          expect(dependency, (await store.getState()).logVersion);
          expect(await store.getNextCommandIds(dependency, count), isEmpty);
        });
      }

      test('satisfies dependencies before advancing each command', () async {
        await _seed(store);
        var dependency = CommandDependency({'z': 1});
        final ids = await store.getNextCommandIds(dependency, 10);
        expect(ids, hasLength(3));
        for (final id in ids) {
          final command = (await store.getStoredCommand(id))!;
          expect(dependency.contains(command.dependency), isTrue);
          dependency = dependency.advance(id);
        }
      });
    });
  }

  for (final sourceBackend in eventStoreTestBackends) {
    for (final targetBackend in eventStoreTestBackends) {
      test('ordered commands transfer from ${sourceBackend.name} '
          'to ${targetBackend.name}', () async {
        final source = await sourceBackend.open();
        addTearDown(source.close);
        final target = await targetBackend.open();
        addTearDown(target.close);
        final commands = await _seed(source.store);
        expect(await target.store.addStoredCommand(commands.first), isTrue);
        var dependency = (await target.store.getState()).logVersion;
        for (var page = 0; page <= commands.length; page++) {
          final ids = await source.store.getNextCommandIds(dependency, 2);
          if (ids.isEmpty) break;
          for (final id in ids) {
            final command = (await source.store.getStoredCommand(id))!;
            expect(await target.store.addStoredCommand(command), isTrue);
            dependency = dependency.advance(id);
          }
        }
        expect(
          (await target.store.getState()).logVersion,
          (await source.store.getState()).logVersion,
        );
      });
    }
  }
}

Future<List<StoredCommand>> _seed(EventStore store) async {
  final commands = [
    _command('z', 1),
    _command('a', 1, dependency: CommandDependency({'z': 1})),
    _command('z', 2, dependency: CommandDependency({'z': 1, 'a': 1})),
    _command('a', 2, dependency: CommandDependency({'z': 2, 'a': 1})),
  ];
  for (final command in commands) {
    expect(await store.addStoredCommand(command), isTrue);
  }
  return commands;
}

StoredCommand _command(
  String actor,
  int sequence, {
  CommandDependency? dependency,
  int eventCount = 1,
}) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: dependency ?? CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    for (var index = 0; index < eventCount; index++)
      StoredCommandEvent(
        streamPath: 'one',
        encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
        occuredAt: DateTime.utc(2026),
      ),
  ],
);
