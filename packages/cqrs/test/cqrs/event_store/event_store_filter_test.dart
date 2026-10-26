import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} log filtering', () {
      late EventStore store;
      late CqrsTestRuntime runtime;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
        runtime = CqrsTestRuntime(eventStore: store);
      });

      for (final (filter, positions) in <(LogFilter, List<int>)>[
        (const LogFilter.all(), [0, 1, 2, 3, 4, 5]),
        (const LogFilter.exact('note/one'), [0, 5]),
        (const LogFilter.startsWith('note/'), [0, 1, 4, 5]),
        (const LogFilter.startsWith(''), [0, 1, 2, 3, 4, 5]),
        (const LogFilter.exact('missing'), []),
        (const LogFilter.startsWith('missing/'), []),
      ]) {
        test('reads matching events for $filter', () async {
          await _appendPaths(store, [
            'note/one',
            'note/one/child',
            'archive/note/one',
            'Note/one',
            'note/two',
            'note/one',
          ]);

          final events = await runtime.logReader(filter, 0).scan().toList();

          expect(events.map((event) => event.position), positions);
        });
      }

      for (final (filter, positions) in <(LogFilter, List<int>)>[
        (const LogFilter.startsWith('a%_/'), [0, 3]),
        (const LogFilter.exact('a%_/one'), [0]),
        (const LogFilter.startsWith("quote'/"), [4]),
        (const LogFilter.startsWith('café/'), [6]),
      ]) {
        test('matches literal patterns for $filter', () async {
          await _appendPaths(store, [
            'a%_/one',
            'abc/one',
            'a%X/one',
            'a%_/two',
            "quote'/one",
            'quoteX/one',
            'café/one',
            'CAFÉ/one',
          ]);

          final events = await runtime.logReader(filter, 0).scan().toList();

          expect(events.map((event) => event.position), positions);
        });
      }

      for (final filter in [
        const LogFilter.exact('note/one'),
        const LogFilter.startsWith('note/'),
      ]) {
        test('fills pages across skipped events for $filter', () async {
          await _appendSparseHistory(store);

          final first = await store.getLogEvents(filter, 0);
          expect(first.data.map((event) => event.position), [1, 4]);
          expect(first.data.map((event) => event.version), [0, 1]);
          expect(first.next, 5);

          final second = await store.getLogEvents(filter, first.next!);
          expect(second.data.single.position, 6);
          expect(second.data.single.version, 2);
          expect(second.next, 7);

          final end = await store.getLogEvents(filter, second.next!);
          expect(end.data, isEmpty);
          expect(end.next, isNull);
        });

        test('includes the supplied global position for $filter', () async {
          await _appendSparseHistory(store);

          final page = await store.getLogEvents(filter, 4);

          expect(page.data.map((event) => event.position), [4, 6]);
          expect(page.next, 7);
        });

        test('treats star stream paths literally for $filter', () async {
          await _appendPaths(store, ['other', '*', 'note/one']);

          final events = await runtime.logReader(filter, 0).scan().toList();

          expect(events.map((event) => event.streamPath), ['note/one']);
        });
      }
    });
  }
}

Future<void> _appendSparseHistory(EventStore store) => _appendPaths(store, [
  'other',
  'note/one',
  'other',
  'other',
  'note/one',
  'other',
  'note/one',
  'other',
]);

Future<void> _appendPaths(EventStore store, List<String> paths) async {
  final time = DateTime.utc(2026);
  final command = StoredCommand(
    commandId: const CommandId('actor', 1),
    dependency: CommandDependency(),
    occuredAt: time,
    events: [
      for (final path in paths)
        StoredCommandEvent(
          streamPath: path,
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: time,
        ),
    ],
  );
  expect(await store.addStoredCommand(command), isTrue);
}
