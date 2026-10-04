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
      expect(await store.getString('missing'), isNull);
    });

    test('stores a value', () async {
      await store.setString('server', 'ws://localhost:7000');

      expect(await store.getString('server'), 'ws://localhost:7000');
    });

    test('replaces an existing value', () async {
      await store.setString('server', 'first');

      await store.setString('server', 'second');

      expect(await store.getString('server'), 'second');
    });

    for (final entry in {
      '': '',
      "a'b": "value 'quoted'",
      '設定.🌱': 'こんにちは🌱',
    }.entries) {
      test('round-trips strings for key ${entry.key}', () async {
        await store.setString(entry.key, entry.value);

        expect(await store.getString(entry.key), entry.value);
      });
    }

    test('sets all values in a batch', () async {
      await store.setAllStrings({'a': 'one', 'b': 'two'});

      expect(await _entries(store), {'a': 'one', 'b': 'two'});
    });

    test('batch writes replace existing values', () async {
      await store.setString('a', 'old');

      await store.setAllStrings({'a': 'new'});

      expect(await store.getString('a'), 'new');
    });

    test('an empty batch preserves existing values', () async {
      await store.setString('a', 'one');

      await store.setAllStrings({});

      expect(await _entries(store), {'a': 'one'});
    });

    test('deletes an existing key', () async {
      await store.setString('a', 'one');

      await store.delete('a');

      expect(await store.getString('a'), isNull);
    });

    test('deleting an absent key succeeds', () async {
      await store.delete('missing');

      expect(await store.getString('missing'), isNull);
    });

    test('deleting a key preserves other values', () async {
      await store.setAllStrings({'a': 'one', 'b': 'two'});

      await store.delete('a');

      expect(await store.getString('b'), 'two');
    });

    test('lists keys in key order', () async {
      await store.setAllStrings({
        'sync.server': 'server',
        'other': 'excluded',
        'sync.enabled': 'true',
      });

      final keys = await store.listKeys('sync.');

      expect(keys, ['sync.enabled', 'sync.server']);
    });

    for (final prefix in ['%', '_', r'\', "'", '設定.', 'Sync.']) {
      test('matches the literal prefix $prefix', () async {
        await store.setString('$prefix.key', 'matched');
        await store.setString('other.key', 'excluded');
        await store.setString('sync.key', 'lowercase');

        final keys = await store.listKeys(prefix);

        expect(keys, ['$prefix.key']);
      });
    }

    test('an empty prefix lists all keys', () async {
      await store.setAllStrings({'': 'empty key', 'a': 'one'});

      expect(await store.listKeys(''), ['', 'a']);
    });

    test('an unmatched prefix returns an empty list', () async {
      await store.setString('a', 'one');

      expect(await store.listKeys('missing'), isEmpty);
    });

    test('repeated migration preserves values', () async {
      await store.setString('a', 'one');

      await store.migrate();

      expect(await store.getString('a'), 'one');
    });
  });

  for (final mixed in [false, true]) {
    test(
      '${mixed ? 'mixed' : 'string'} batches roll back on storage failure',
      () async {
        final database = IsolateSqlite();
        await database.openInMemory();
        final store = SqliteKv(database);
        addTearDown(store.close);
        await store.migrate();
        await store.setString('existing', 'original');
        await database.transaction((tx) {
          tx.execute('''
          CREATE TRIGGER reject_key BEFORE INSERT ON kv_entry
          WHEN NEW.key = 'rejected'
          BEGIN
            SELECT RAISE(ABORT, 'Rejected test key');
          END;
        ''');
        });

        final write = mixed
            ? store.setAll({
                'existing': true,
                'new': false,
                'rejected': 'value',
              })
            : store.setAllStrings({
                'existing': 'replacement',
                'new': 'value',
                'rejected': 'value',
              });
        await expectLater(write, throwsA(isA<SqliteException>()));

        expect(await _entries(store), {'existing': 'original'});
      },
    );
  }

  test('values persist across database reopen', () async {
    final directory = await Directory.systemTemp.createTemp('kv-test-');
    addTearDown(() => directory.delete(recursive: true));
    final filename = '${directory.path}/system.sqlite';
    final database = IsolateSqlite();
    await database.open(filename);
    final store = SqliteKv(database);
    try {
      await store.migrate();
      await store.setString('server', 'ws://localhost:7000');
    } finally {
      await store.close();
    }

    final reopenedDatabase = IsolateSqlite();
    await reopenedDatabase.open(filename);
    final reopened = SqliteKv(reopenedDatabase);
    addTearDown(reopened.close);
    await reopened.migrate();

    expect(await reopened.getString('server'), 'ws://localhost:7000');
  });
}

Future<Map<String, String>> _entries(Kv store) async => {
  for (final key in await store.listKeys(''))
    key: (await store.getString(key))!,
};
