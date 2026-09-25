import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} string actors', () {
      late EventStore store;
      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      for (final actor in ['', 'Alice', 'alice']) {
        test('preserves actor "$actor" without registration', () async {
          await store.saveChanges(_changes(actor));
          final command = (await store.getStoredCommand(CommandId(actor, 1)))!;
          expect(command.commandId.actor, actor);
          expect(
            (await store.getLogEvents(0)).data.single.eventId,
            EventId(actor, 1, 0),
          );
          expect(
            (await store.getState()).logVersion,
            CommandDependency({actor: 1}),
          );
        });
      }

      test('actor identity is case sensitive', () async {
        await store.saveChanges(_changes('Alice'));
        await store.saveChanges(_changes('alice', version: 0));
        expect(
          (await store.getState()).logVersion,
          CommandDependency({'Alice': 1, 'alice': 1}),
        );
      });

      test(
        'two runtimes share storage with independent actor sequences',
        () async {
          final alice = _runtime(store, 'alice');
          final bob = _runtime(store, 'bob');
          await alice.execute(const _Append());
          await bob.execute(const _Append());
          await alice.execute(const _Append());
          final commands = [
            (await store.getStoredCommand(const CommandId('alice', 1)))!,
            (await store.getStoredCommand(const CommandId('bob', 1)))!,
            (await store.getStoredCommand(const CommandId('alice', 2)))!,
          ];
          expect(commands[0].dependency, CommandDependency());
          expect(commands[1].dependency, CommandDependency({'alice': 1}));
          expect(
            commands[2].dependency,
            CommandDependency({'alice': 1, 'bob': 1}),
          );
          final events = await alice.logReader(0).scan().toList();
          expect(events.map((event) => event.eventId), [
            EventId('alice', 1, 0),
            EventId('bob', 1, 0),
            EventId('alice', 2, 0),
          ]);
        },
      );

      test(
        'imported and local commands share the same actor sequence',
        () async {
          expect(await store.addStoredCommand(_stored('alice')), isTrue);
          await store.saveChanges(_changes('alice', version: 0));
          expect(
            await store.getStoredCommand(const CommandId('alice', 2)),
            isNotNull,
          );
          expect(
            (await store.getState()).logVersion,
            CommandDependency({'alice': 2}),
          );
        },
      );

      for (final sequence in [-1, 0, 2]) {
        test('rejects first sequence $sequence without changes', () async {
          expect(
            await store.addStoredCommand(_stored('alice', sequence: sequence)),
            isFalse,
          );
          expect((await store.getState()).lastCommandLogPosition, isNull);
          expect(await store.getStreamVersion('one'), isNull);
          expect(await store.addStoredCommand(_stored('alice')), isTrue);
          expect((await store.getLogEvents(0)).data.single.position, 0);
        });
      }

      test(
        'missing dependencies reject a command until history arrives',
        () async {
          final pending = _stored(
            'bob',
            dependency: CommandDependency({'alice': 2}),
          );
          expect(await store.addStoredCommand(pending), isFalse);
          expect(await store.addStoredCommand(_stored('alice')), isTrue);
          expect(await store.addStoredCommand(pending), isFalse);
          expect(
            (await store.getState()).logVersion,
            CommandDependency({'alice': 1}),
          );
          expect(
            await store.addStoredCommand(_stored('alice', sequence: 2)),
            isTrue,
          );
          expect(await store.addStoredCommand(pending), isTrue);
          expect(
            (await store.getStoredCommand(pending.commandId))!.toJson(),
            pending.toJson(),
          );
        },
      );

      test('concurrent duplicate stored commands have one winner', () async {
        final command = _stored('alice');
        final results = await Future.wait([
          store.addStoredCommand(command),
          store.addStoredCommand(command),
        ]);
        expect(results.where((accepted) => accepted), hasLength(1));
        expect((await store.getStatistics()).eventCount, 1);
      });

      test('concurrent actors allocate independent first sequences', () async {
        await Future.wait([
          store.saveChanges(_changes('alice', path: 'alice')),
          store.saveChanges(_changes('bob', path: 'bob')),
        ]);
        expect(
          (await store.getState()).logVersion,
          CommandDependency({'alice': 1, 'bob': 1}),
        );
        expect(
          await store.getStoredCommand(const CommandId('alice', 1)),
          isNotNull,
        );
        expect(
          await store.getStoredCommand(const CommandId('bob', 1)),
          isNotNull,
        );
      });

      test('stored command dependencies can refer to the same actor', () async {
        expect(await store.addStoredCommand(_stored('alice')), isTrue);
        final command = _stored(
          'alice',
          sequence: 2,
          dependency: CommandDependency({'alice': 1}),
        );
        expect(await store.addStoredCommand(command), isTrue);
        expect(
          (await store.getStoredCommand(command.commandId))!.toJson(),
          command.toJson(),
        );
      });
    });
  }

  for (final sourceBackend in eventStoreTestBackends) {
    for (final targetBackend in eventStoreTestBackends) {
      test(
        'stored commands transfer from ${sourceBackend.name} to ${targetBackend.name}',
        () async {
          final source = await sourceBackend.open();
          addTearDown(source.close);
          final target = await targetBackend.open();
          addTearDown(target.close);
          // Establish histories in a different order to verify identity is unchanged.
          final alice = _stored('alice');
          final bob = _stored('bob');
          expect(await source.store.addStoredCommand(alice), isTrue);
          expect(await source.store.addStoredCommand(bob), isTrue);
          expect(await target.store.addStoredCommand(bob), isTrue);
          expect(await target.store.addStoredCommand(alice), isTrue);
          await source.store.saveChanges(
            _changes(
              'writer/actor',
              path: 'local',
              dependency: CommandDependency({'alice': 1, 'bob': 1}),
            ),
          );
          final original =
              (await source.store.getStoredCommand(
                const CommandId('writer/actor', 1),
              ))!;
          final transferred = StoredCommand.fromJson(
            jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
          );
          expect(await target.store.addStoredCommand(transferred), isTrue);
          expect(
            (await target.store.getStoredCommand(original.commandId))!.toJson(),
            original.toJson(),
          );
          expect(
            (await target.store.getState()).logVersion,
            CommandDependency({'alice': 1, 'bob': 1, 'writer/actor': 1}),
          );
        },
      );
    }
  }
}

CqrsRuntime _runtime(EventStore store, String actor) => CqrsRuntime(
  eventStore: store,
  actor: actor,
  logger: const NoopLogger(),
  timeProvider: FakeTimeProviderStatic.zero(),
)..eventRegistry.add(const _StringCodec());

class _Append implements Command {
  const _Append();

  @override
  Future<void> handle(CommandContextApi context) async {
    final stream = context.stream<String>('one');
    await stream.lockLatest();
    stream.append('value');
  }
}

class _StringCodec implements EventCodec<String> {
  const _StringCodec();
  @override
  String get kind => 'string';
  @override
  Uint8List toBytes(String event) => Uint8List.fromList(utf8.encode(event));
  @override
  String fromBytes(Uint8List bytes) => utf8.decode(bytes);
}

StoredCommand _stored(
  String actor, {
  int sequence = 1,
  CommandDependency? dependency,
}) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: dependency ?? CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    StoredCommandEvent(
      streamPath: 'one',
      encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
      occuredAt: DateTime.utc(2026),
    ),
  ],
);

CommandChanges _changes(
  String actor, {
  String path = 'one',
  int? version,
  CommandDependency? dependency,
}) => CommandChanges(
  actor: actor,
  dependency: dependency ?? CommandDependency(),
  occuredAt: DateTime.utc(2026),
  locks: [StreamLock(streamPath: path, originatingStreamVersion: version)],
  events: [
    EventAppend(
      streamPath: path,
      encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
      occuredAt: DateTime.utc(2026),
    ),
  ],
);
