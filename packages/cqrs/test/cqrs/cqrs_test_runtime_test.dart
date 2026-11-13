import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  final seededAt = DateTime.utc(2026, 1, 2);

  test('uses a memory store and zero timestamp by default', () async {
    final runtime = CqrsTestRuntime();
    runtime.eventRegistry.add(const _ValueEventCodec());

    await runtime.execute(const _AppendValue('one'));

    final events = (await runtime.resolveProjection(_ValueProjection())).events;
    expect(events, hasLength(1));
    expect(events.single.event.value, 'one');
    expect(events.single.occuredAt, DateTime.utc(1970));
  });

  test('uses an injected store and time provider', () async {
    final database = MemoryEventStore();
    final store = database;
    final runtime = CqrsTestRuntime(
      eventStore: store,
      timeProvider: FakeTimeProviderStatic(seededAt),
    );
    runtime.eventRegistry.add(const _ValueEventCodec());

    await runtime.execute(const _AppendValue('one'));

    final bundle = await database.getStoredCommand(CommandId('test-actor', 1));
    expect(bundle!.events, hasLength(1));
    expect(bundle.events.single.occuredAt, seededAt);
    final events = (await runtime.resolveProjection(_ValueProjection())).events;
    expect(events.single.occuredAt, seededAt);
  });

  test('seeds an event for projection resolution', () async {
    final store = MemoryEventStore();
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());

    expect(
      await runtime.seedEvents([
        TestEvent(
          actor: 'a',
          stream: 'value/one',
          event: const _ValueEvent('seeded'),
          occuredAt: seededAt,
        ),
      ]),
      same(runtime),
    );

    final events = (await runtime.resolveProjection(_ValueProjection())).events;
    expect(events, hasLength(1));
    expect(events.single.event.value, 'seeded');
    expect(events.single.occuredAt, seededAt);
  });

  test('seeds multiple streams in the supplied order', () async {
    final database = MemoryEventStore();
    final store = database;
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());
    final later = seededAt.add(const Duration(days: 1));

    await runtime.seedEvents([
      TestEvent(
        actor: 'a',
        stream: 'value/one',
        event: const _ValueEvent('first'),
        occuredAt: seededAt,
      ),
      TestEvent(
        actor: 'b',
        stream: 'value/two',
        event: const _ValueEvent('second'),
        occuredAt: later,
      ),
      TestEvent(
        actor: 'a',
        stream: 'value/one',
        event: const _ValueEvent('third'),
        occuredAt: later,
      ),
    ]);

    final events = (await runtime.resolveProjection(_ValueProjection())).events;
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
    expect(events.map((event) => event.actor), ['a', 'b', 'a']);
    expect(events.map((event) => event.logPosition), [0, 1, 2]);
    expect(
      (await database.getLogEvents(
        const LogFilter.all(),
        0,
      )).data.map((event) => event.streamPath),
      ['value/one', 'value/two', 'value/one'],
    );
    final log = (await database.getLogEvents(const LogFilter.all(), 0)).data;
    expect(log.map((event) => event.version), [0, 0, 1]);
  });

  test('seeds an existing stream before the next command', () async {
    final database = MemoryEventStore();
    final store = database;
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());
    await runtime.execute(const _AppendValue('one'));

    await runtime.seedEvents([
      TestEvent(
        actor: 'test-actor',
        stream: 'value/one',
        event: const _ValueEvent('seeded'),
        occuredAt: seededAt,
      ),
    ]);
    await runtime.execute(const _AppendValue('one'));

    final events = (await runtime.resolveProjection(_ValueProjection())).events;
    expect(events.map((event) => event.event.value), ['one', 'seeded', 'one']);
    expect(events.map((event) => event.logPosition), [0, 1, 2]);
    expect((await database.getStreamInfo('value/one')).version, 2);
  });

  test('rejects unregistered seed events before writing', () async {
    final database = MemoryEventStore();
    final store = database;
    final runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const _ValueEventCodec());

    await expectLater(
      runtime.seedEvents([
        TestEvent(
          actor: 'a',
          stream: 'value/one',
          event: const _ValueEvent('registered'),
          occuredAt: seededAt,
        ),
        TestEvent(
          actor: 'a',
          stream: 'value/one',
          event: Object(),
          occuredAt: seededAt,
        ),
      ]),
      throwsA(isA<EventCodecException>()),
    );

    expect(
      (await database.getLogEvents(const LogFilter.all(), 0)).data,
      isEmpty,
    );
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

final class _AppendValue implements Command {
  final String value;

  const _AppendValue(this.value);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    final stream = ctx.stream<_ValueEvent>('value/$value');
    await stream.lockLatest();
    stream.append(_ValueEvent(value));
  }
}

final class _ValueModel {
  final events = <EventEnvelope<_ValueEvent>>[];
}

final class _ValueProjection implements Projection<_ValueModel, _ValueEvent> {
  @override
  String get name => 'Values';

  @override
  LogFilter get filter => const LogFilter.startsWith('value/');

  @override
  ProjectionLoad<_ValueModel> load() => ProjectionLoad.initial(_ValueModel());

  @override
  void apply(_ValueModel model, EventEnvelope<_ValueEvent> envelope) =>
      model.events.add(envelope);

  @override
  void onStreamDeleted(_ValueModel model, StreamDeletion deletion) {}
}
