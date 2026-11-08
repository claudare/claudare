import 'package:fts/fts.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFts fts;

  setUp(() {
    fts = MemoryFts();
  });

  test('an empty index returns no results', () async {
    expect(await fts.query('note', 10), isEmpty);
  });

  test('matches word prefixes', () async {
    await fts.upsert('matched', 'a notebook', 1);
    await fts.upsert('unmatched', 'a footnote', 2);

    expect(await fts.query('note', 10), ['matched']);
  });

  test('prefix matching is case-insensitive', () async {
    await fts.upsert('upper', 'Note', 1);
    await fts.upsert('lower', 'note', 2);

    expect(await fts.query('No', 10), unorderedEquals(['upper', 'lower']));
  });

  for (final whitespace in [' ', '\t', '\n', '\r\n', ' \t\n ']) {
    test('splits content at ${whitespace.codeUnits}', () async {
      await fts.upsert('id', '${whitespace}first${whitespace}second', 1);

      expect(await fts.query('sec', 10), ['id']);
    });

    test('splits queries at ${whitespace.codeUnits}', () async {
      await fts.upsert('first', 'first', 1);
      await fts.upsert('second', 'second', 2);

      expect(
        await fts.query('${whitespace}fir${whitespace}sec$whitespace', 10),
        unorderedEquals(['first', 'second']),
      );
    });
  }

  test('ranks ids by matching word occurrences', () async {
    await fts.upsert('one', 'note', 1);
    await fts.upsert('three', 'note notebook note', 2);
    await fts.upsert('two', 'notebook note', 3);

    expect(await fts.query('note', 10), ['three', 'two', 'one']);
  });

  test('combines hits from independent query words', () async {
    await fts.upsert('one', 'note', 1);
    await fts.upsert('three', 'note task todo', 2);
    await fts.upsert('two', 'task todo', 3);

    expect(await fts.query('note ta to', 10), ['three', 'two', 'one']);
  });

  test('limits results after ranking', () async {
    await fts.upsert('one', 'note', 1);
    await fts.upsert('two', 'note notebook', 2);

    expect(await fts.query('note', 1), ['two']);
  });

  test('a zero result count returns no results', () async {
    await fts.upsert('id', 'note', 1);

    expect(await fts.query('note', 0), isEmpty);
  });

  for (final query in ['', ' \t\n ', 'missing']) {
    test('returns no results for ${query.codeUnits}', () async {
      await fts.upsert('id', 'note', 1);

      expect(await fts.query(query, 10), isEmpty);
    });
  }

  test('upsert replaces the words for an existing id', () async {
    await fts.upsert('id', 'old', 1);
    await fts.upsert('id', 'new', 2);

    expect(await fts.query('old new', 10), ['id']);
    expect(await fts.query('old', 10), isEmpty);
  });

  test('empty content removes previous searchable words', () async {
    await fts.upsert('id', 'note', 1);
    await fts.upsert('id', ' \t\n ', 2);

    expect(await fts.query('note', 10), isEmpty);
  });

  test('delete removes only the requested id', () async {
    await fts.upsert('removed', 'note', 1);
    await fts.upsert('retained', 'note', 2);
    await fts.delete('removed', 3);

    expect(await fts.query('note', 10), ['retained']);
  });

  test('the initial revision is null', () async {
    expect(await fts.getRevision(), isNull);
  });

  test('upsert stores the last applied revision', () async {
    await fts.upsert('first', 'note', 10);
    await fts.upsert('second', 'task', 5);

    expect(await fts.getRevision(), 5);
  });

  for (final id in ['existing', 'missing']) {
    test('deleting $id stores the revision', () async {
      await fts.upsert('existing', 'note', 1);
      await fts.delete(id, 2);

      expect(await fts.getRevision(), 2);
    });
  }

  test('queries preserve the revision', () async {
    await fts.upsert('id', 'note', 1);
    await fts.query('note', 10);

    expect(await fts.getRevision(), 1);
  });

  test('instances have independent indexes', () async {
    await fts.upsert('id', 'note', 1);

    expect(await MemoryFts().query('note', 10), isEmpty);
  });

  test('instances have independent revisions', () async {
    await fts.upsert('id', 'note', 1);

    expect(await MemoryFts().getRevision(), isNull);
  });
}
