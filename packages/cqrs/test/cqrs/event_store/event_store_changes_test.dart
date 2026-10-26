import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} change subscriptions', () {
      late EventStore store;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      test('local write emits one command and one change per event', () async {
        final command = store.commandChanges.first;
        final events = store.eventChanges.take(4).toList();

        await store.saveChanges(_changes(count: 4));

        final change = await command;
        expect(change.origin, ChangeOrigin.local);
        expect(change.commandId, CommandId('actor', 1));
        expect(
          (await store.getState()).logVersion,
          CommandDependency({'actor': 1}),
        );
        expect((await events).map((event) => event.stream), [
          'test',
          'test',
          'test',
          'test',
        ]);
      });

      test('remote write preserves command ID and event order', () async {
        final command = store.commandChanges.first;
        final events = store.eventChanges.take(3).toList();
        final stored = _storedCommand(CommandId('remote', 1), [
          'test',
          'other',
          'test',
        ]);

        expect(await store.addStoredCommand(stored), isTrue);

        final change = await command;
        expect(change.origin, ChangeOrigin.remote);
        expect(change.commandId, stored.commandId);
        expect((await events).map((event) => event.stream), [
          'test',
          'other',
          'test',
        ]);
      });

      test('empty and rejected local writes emit no changes', () async {
        final commands = <CommandChange>[];
        final events = <EventChange>[];
        final commandSubscription = store.commandChanges.listen(commands.add);
        final eventSubscription = store.eventChanges.listen(events.add);
        addTearDown(commandSubscription.cancel);
        addTearDown(eventSubscription.cancel);

        await store.saveChanges(_changes(count: 0));
        await expectLater(
          store.saveChanges(_changes(dependency: CommandDependency({'x': 1}))),
          throwsStateError,
        );
        await store.saveChanges(_changes());
        await Future<void>.delayed(Duration.zero);

        expect(commands, hasLength(1));
        expect(commands.single.commandId, CommandId('actor', 1));
        expect(events.map((event) => event.stream), ['test']);
      });

      test('rolled back write emits no changes', () async {
        final commands = <CommandChange>[];
        final events = <EventChange>[];
        final commandSubscription = store.commandChanges.listen(commands.add);
        final eventSubscription = store.eventChanges.listen(events.add);
        addTearDown(commandSubscription.cancel);
        addTearDown(eventSubscription.cancel);
        final valid = _changes();

        await expectLater(
          store.saveChanges(
            CommandChanges(
              actor: valid.actor,
              dependency: valid.dependency,
              occuredAt: valid.occuredAt,
              locks: valid.locks,
              events: [valid.events.single, _FailingAppend()],
            ),
          ),
          throwsA(isA<EventStoreException>()),
        );
        await store.saveChanges(valid);
        await Future<void>.delayed(Duration.zero);

        expect(commands, hasLength(1));
        expect(commands.single.commandId, CommandId('actor', 1));
        expect(events, hasLength(1));
      });

      test('rejected remote write emits no changes', () async {
        final commands = <CommandChange>[];
        final events = <EventChange>[];
        final commandSubscription = store.commandChanges.listen(commands.add);
        final eventSubscription = store.eventChanges.listen(events.add);
        addTearDown(commandSubscription.cancel);
        addTearDown(eventSubscription.cancel);

        expect(
          await store.addStoredCommand(
            _storedCommand(CommandId('remote', 2), ['test']),
          ),
          isFalse,
        );
        expect(
          await store.addStoredCommand(
            _storedCommand(CommandId('remote', 1), ['test']),
          ),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        expect(commands, hasLength(1));
        expect(events, hasLength(1));
      });

      test('both channels broadcast to concurrent listeners', () async {
        final firstCommand = store.commandChanges.first;
        final secondCommand = store.commandChanges.first;
        final firstEvent = store.eventChanges.first;
        final secondEvent = store.eventChanges.first;

        await store.saveChanges(_changes());

        expect((await firstCommand).commandId, CommandId('actor', 1));
        expect((await secondCommand).commandId, CommandId('actor', 1));
        expect((await firstEvent).stream, 'test');
        expect((await secondEvent).stream, 'test');
      });

      test('new listeners receive only future writes', () async {
        await store.saveChanges(_changes());
        final command = store.commandChanges.first;
        final event = store.eventChanges.first;

        await store.saveChanges(_changes(version: 0));

        expect((await command).commandId, CommandId('actor', 2));
        expect((await event).stream, 'test');
      });
    });
  }
}

CommandChanges _changes({
  int count = 1,
  int? version,
  CommandDependency? dependency,
}) {
  final time = DateTime.utc(2026);
  return CommandChanges(
    actor: 'actor',
    dependency: dependency ?? CommandDependency(),
    occuredAt: time,
    locks: [StreamLock(streamPath: 'test', originatingStreamVersion: version)],
    events: [
      for (var index = 0; index < count; index++)
        EventAppend(
          streamPath: 'test',
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: time,
        ),
    ],
  );
}

StoredCommand _storedCommand(CommandId commandId, List<String> streams) {
  final time = DateTime.utc(2026);
  return StoredCommand(
    commandId: commandId,
    dependency: CommandDependency(),
    occuredAt: time,
    events: [
      for (final stream in streams)
        StoredCommandEvent(
          streamPath: stream,
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: time,
        ),
    ],
  );
}

final class _FailingAppend extends EventAppend {
  _FailingAppend()
    : super(
        streamPath: 'test',
        encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
        occuredAt: DateTime.utc(2026),
      );

  @override
  EncodedEvent get encodedEvent =>
      throw const FormatException('injected failure');
}
