import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  final seededAt = DateTime.utc(2026, 1, 2);

  test('uses a memory store and zero timestamp by default', () async {
    final runtime = CqrsTestRuntime();
    runtime.eventRegistry.add(const _ValueEventCodec());

    await runtime.execute(const _AppendValue(), const _AppendValueInput('one'));

    final events = await runtime.resolve(_ValueAggregate(), 'one');
    expect(events, hasLength(1));
    expect(events.single.event.value, 'one');
    expect(events.single.occuredAt, DateTime.utc(1970));
  });

  test('uses an injected store, logger, and time provider', () async {
    final database = MemoryEventDatabase();
    final store = EventStore(database);
    final runtime = CqrsTestRuntime(
      eventStore: store,
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic(seededAt),
    );
    runtime.eventRegistry.add(const _ValueEventCodec());

    await runtime.execute(const _AppendValue(), const _AppendValueInput('one'));

    final applied = await database.getAppliedEvents(CommandId(0, 1));
    expect(applied, hasLength(1));
    expect(applied.single.occuredAt, seededAt);
    final events = await runtime.resolve(_ValueAggregate(), 'one');
    expect(events.single.occuredAt, seededAt);
  });

  test('seeds an event for aggregate resolution', () async {
    final store = EventStore(MemoryEventDatabase());
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());

    expect(
      await runtime.seedEvents([
        TestEvent('value/one', const _ValueEvent('seeded'), seededAt),
      ]),
      same(runtime),
    );

    final events = await runtime.resolve(_ValueAggregate(), 'one');
    expect(events, hasLength(1));
    expect(events.single.event.value, 'seeded');
    expect(events.single.occuredAt, seededAt);
  });

  test('seeds multiple streams in the supplied order', () async {
    final database = MemoryEventDatabase();
    final store = EventStore(database);
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());
    final later = seededAt.add(const Duration(days: 1));

    await runtime.seedEvents([
      TestEvent('value/one', const _ValueEvent('first'), seededAt),
      TestEvent('value/two', const _ValueEvent('second'), later),
      TestEvent('value/one', const _ValueEvent('third'), later),
    ]);

    final events = await runtime.resolve(_ValueAggregate(), 'one');
    expect(events.map((event) => event.event.value), [
      'first',
      'second',
      'third',
    ]);
    expect(events.map((event) => event.streamPath), [
      'value/one',
      'value/two',
      'value/one',
    ]);
    expect(events.map((event) => event.occuredAt), [seededAt, later, later]);
    expect(
      (await database.getLocalEvents(
        0,
        10,
      )).data.map((event) => event.streamPath),
      ['value/one', 'value/two', 'value/one'],
    );
    final commands = await database.getAppliedCommands(0, 10);
    final applied = <AppliedEvent>[
      for (final command in commands)
        ...await database.getAppliedEvents(command.commandId),
    ];
    expect(applied.map((event) => event.streamVersion), [0, 0, 1]);
  });

  test('seeds an existing stream before the next command', () async {
    final database = MemoryEventDatabase();
    final store = EventStore(database);
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());
    await runtime.execute(const _AppendValue(), const _AppendValueInput('one'));

    await runtime.seedEvents([
      TestEvent('value/one', const _ValueEvent('seeded'), seededAt),
    ]);
    await runtime.execute(const _AppendValue(), const _AppendValueInput('one'));

    final events = await runtime.resolve(_ValueAggregate(), 'one');
    expect(events.map((event) => event.event.value), ['one', 'seeded', 'one']);
    expect(await database.getStreamVersion('value/one'), 2);
  });

  test('rejects unregistered seed events before writing', () async {
    final database = MemoryEventDatabase();
    final store = EventStore(database);
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());

    await expectLater(
      runtime.seedEvents([
        TestEvent('value/one', const _ValueEvent('registered'), seededAt),
        TestEvent('value/one', Object(), seededAt),
      ]),
      throwsA(isA<EventCodecException>()),
    );

    expect((await database.getLocalEvents(0, 1)).data, isEmpty);
  });
}

final class _ValueEvent {
  final String value;

  const _ValueEvent(this.value);
}

final class _ValueEventCodec implements EventCodec<_ValueEvent> {
  const _ValueEventCodec();

  @override
  String get kind => 'value';

  @override
  Uint8List toBytes(_ValueEvent event) =>
      Uint8List.fromList(utf8.encode(event.value));

  @override
  _ValueEvent fromBytes(Uint8List bytes) => _ValueEvent(utf8.decode(bytes));
}

final class _AppendValueInput implements CommandInput {
  final String value;

  const _AppendValueInput(this.value);

  @override
  String get kind => 'appendValue';

  @override
  Uint8List encode() => Uint8List.fromList(utf8.encode(value));
}

final class _AppendValue implements Command<_AppendValueInput> {
  const _AppendValue();

  @override
  Future<void> handle(_AppendValueInput input, CommandContext ctx) async {
    final stream = ctx.stream<_ValueEvent>('value/${input.value}');
    await stream.lockLatest();
    stream.append(_ValueEvent(input.value));
  }
}

final class _ValueAggregate
    implements
        Aggregate<
          _ValueEvent,
          String,
          List<EventEnvelope<_ValueEvent, String>>
        > {
  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => StreamRouteWildcard('value/*');

  @override
  Snapshotter<List<EventEnvelope<_ValueEvent, String>>>? get snapshotter =>
      null;

  @override
  List<EventEnvelope<_ValueEvent, String>> initialState() => [];

  @override
  bool canApply(EventEnvelope<_ValueEvent, String> envelope) => true;

  @override
  void apply(
    List<EventEnvelope<_ValueEvent, String>> state,
    EventEnvelope<_ValueEvent, String> envelope,
  ) => state.add(envelope);
}
