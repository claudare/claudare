import 'dart:io';

import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/kv.dart';
import 'package:test/test.dart';

void main() {
  group('SQLite KV', () {
    late SqliteKv store;

    setUp(() async {
      store = await KvTestHelper.createMemoryKv();
    });
    tearDown(() => store.close());

    test('returns null for an absent key', () async {
      expect(await store.get('missing'), isNull);
    });

    test('stores a value', () async {
      await store.set('server', 'ws://localhost:7000');

      expect(await store.get('server'), 'ws://localhost:7000');
    });

    test('replaces an existing value', () async {
      await store.set('server', 'first');

      await store.set('server', 'second');

      expect(await store.get('server'), 'second');
    });

    for (final entry in [
      const KeyValue(key: '', value: ''),
      const KeyValue(key: "a'b", value: "value 'quoted'"),
      const KeyValue(key: '設定.🌱', value: 'こんにちは🌱'),
    ]) {
      test('round-trips strings for key ${entry.key}', () async {
        await store.set(entry.key, entry.value);

        expect(await store.get(entry.key), entry.value);
      });
    }

    test('sets all values in a batch', () async {
      await store.setAll([
        const KeyValue(key: 'a', value: 'one'),
        const KeyValue(key: 'b', value: 'two'),
      ]);

      expect(await _entries(store), {'a': 'one', 'b': 'two'});
    });

    test('batch writes replace existing values', () async {
      await store.set('a', 'old');

      await store.setAll([const KeyValue(key: 'a', value: 'new')]);

      expect(await store.get('a'), 'new');
    });

    test('the last batch entry wins for duplicate keys', () async {
      await store.setAll([
        const KeyValue(key: 'a', value: 'first'),
        const KeyValue(key: 'a', value: 'last'),
      ]);

      expect(await store.get('a'), 'last');
    });

    test('an empty batch preserves existing values', () async {
      await store.set('a', 'one');

      await store.setAll([]);

      expect(await _entries(store), {'a': 'one'});
    });

    test('deletes an existing key', () async {
      await store.set('a', 'one');

      await store.delete('a');

      expect(await store.get('a'), isNull);
    });

    test('deleting an absent key succeeds', () async {
      await store.delete('missing');

      expect(await store.get('missing'), isNull);
    });

    test('deleting a key preserves other values', () async {
      await store.setAll([
        const KeyValue(key: 'a', value: 'one'),
        const KeyValue(key: 'b', value: 'two'),
      ]);

      await store.delete('a');

      expect(await store.get('b'), 'two');
    });

    test('lists entries in key order', () async {
      await store.setAll([
        const KeyValue(key: 'sync.server', value: 'server'),
        const KeyValue(key: 'other', value: 'excluded'),
        const KeyValue(key: 'sync.enabled', value: 'true'),
      ]);

      final entries = await store.list('sync.');

      expect(entries.map((entry) => entry.key), [
        'sync.enabled',
        'sync.server',
      ]);
      expect(entries.map((entry) => entry.value), ['true', 'server']);
    });

    for (final prefix in ['%', '_', r'\', "'", '設定.', 'Sync.']) {
      test('matches the literal prefix $prefix', () async {
        await store.set('$prefix.key', 'matched');
        await store.set('other.key', 'excluded');
        await store.set('sync.key', 'lowercase');

        final entries = await store.list(prefix);

        expect(entries.map((entry) => entry.key), ['$prefix.key']);
      });
    }

    test('an empty prefix lists all entries', () async {
      await store.setAll([
        const KeyValue(key: '', value: 'empty key'),
        const KeyValue(key: 'a', value: 'one'),
      ]);

      expect(await _entries(store), {'': 'empty key', 'a': 'one'});
    });

    test('an unmatched prefix returns an empty list', () async {
      await store.set('a', 'one');

      expect(await store.list('missing'), isEmpty);
    });

    test('repeated migration preserves values', () async {
      await store.set('a', 'one');

      await store.migrate();

      expect(await store.get('a'), 'one');
    });
  });

  test('values persist across database reopen', () async {
    final directory = await Directory.systemTemp.createTemp('kv-test-');
    addTearDown(() => directory.delete(recursive: true));
    final filename = '${directory.path}/system.sqlite';
    final database = IsolateSqlite();
    await database.open(filename);
    final store = SqliteKv(database);
    try {
      await store.migrate();
      await store.set('server', 'ws://localhost:7000');
    } finally {
      await store.close();
    }

    final reopenedDatabase = IsolateSqlite();
    await reopenedDatabase.open(filename);
    final reopened = SqliteKv(reopenedDatabase);
    addTearDown(reopened.close);
    await reopened.migrate();

    expect(await reopened.get('server'), 'ws://localhost:7000');
  });
}

Future<Map<String, String>> _entries(Kv store) async => {
  for (final entry in await store.list('')) entry.key: entry.value,
};
