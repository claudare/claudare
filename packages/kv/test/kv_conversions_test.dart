import 'package:kv/kv.dart';
import 'package:test/test.dart';

void main() {
  late Kv store;

  setUp(() async {
    final sqlite = await KvTestHelper.createMemoryKv();
    addTearDown(sqlite.close);
    store = sqlite;
  });

  test('typed string values round-trip', () async {
    await store.setTyped<String>('key', 'value');

    expect(await store.getTyped<String>('key'), 'value');
  });

  for (final value in [true, false]) {
    test('boolean helpers round-trip $value', () async {
      await store.setBool('enabled', value);

      expect(await store.getBool('enabled'), value);
    });

    test('boolean helpers store the string $value', () async {
      await store.setBool('enabled', value);

      expect(await store.getString('enabled'), '$value');
    });

    test('typed boolean values round-trip $value', () async {
      await store.setTyped<bool>('enabled', value);

      expect(await store.getTyped<bool>('enabled'), value);
    });
  }

  test('absent booleans return null', () async {
    expect(await store.getBool('missing'), isNull);
  });

  test('absent typed strings return null', () async {
    expect(await store.getTyped<String>('missing'), isNull);
  });

  test('absent typed booleans return null', () async {
    expect(await store.getTyped<bool>('missing'), isNull);
  });

  test('absent keys return null for unsupported requested types', () async {
    expect(await store.getTyped<int>('missing'), isNull);
  });

  for (final value in ['', 'TRUE', '1']) {
    test('boolean reads reject "$value"', () async {
      await store.setString('enabled', value);

      await expectLater(store.getBool('enabled'), throwsStateError);
    });
  }

  test('typed reads reject unsupported requested types', () async {
    await store.setString('number', '1');

    await expectLater(store.getTyped<int>('number'), throwsUnsupportedError);
  });

  for (final value in <dynamic>['value', true, false]) {
    test(
      'typed writes convert runtime ${value.runtimeType} value $value',
      () async {
        await store.setTyped<dynamic>('key', value);

        expect(await store.getString('key'), '$value');
      },
    );
  }

  for (final value in <dynamic>[null, 1, 1.5, <String>[]]) {
    test(
      'typed writes reject ${value.runtimeType} without replacing values',
      () async {
        await store.setString('key', 'original');

        await expectLater(
          store.setTyped<dynamic>('key', value),
          throwsUnsupportedError,
        );

        expect(await store.getString('key'), 'original');
      },
    );

    test('mixed batches reject ${value.runtimeType} before writing', () async {
      await store.setString('existing', 'original');

      await expectLater(
        store.setAll({
          'existing': 'replacement',
          'new': true,
          'unsupported': value,
        }),
        throwsUnsupportedError,
      );

      expect(await store.getString('existing'), 'original');
      expect(await store.listKeys(''), ['existing']);
    });
  }

  test('mixed batches persist strings and booleans', () async {
    await store.setAll({'group': '001', 'enabled': true, 'disabled': false});

    expect(
      {
        for (final key in await store.listKeys(''))
          key: await store.getString(key),
      },
      {'group': '001', 'enabled': 'true', 'disabled': 'false'},
    );
  });

  test('an empty mixed batch preserves existing values', () async {
    await store.setString('key', 'original');

    await store.setAll({});

    expect(await store.getString('key'), 'original');
  });
}
