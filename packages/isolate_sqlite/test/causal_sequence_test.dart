import 'package:test/test.dart';
import 'package:isolate_sqlite/src/isolate_sqlite.dart';

class CausalDb {
  final IsolateSqlite db;
  const CausalDb(this.db);

  Future<void> setup() async {
    await db.execute('''
      CREATE TABLE event (
        actor_id INTEGER NOT NULL,
        actor_sequence INTEGER NOT NULL,
        causal_sequence INTEGER NOT NULL,
        local_sequence INTEGER NOT NULL,
        PRIMARY KEY (local_sequence)
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_actor_sequence ON event(actor_id, actor_sequence);',
    );
    await db.execute(
      'CREATE INDEX idx_causal_sequence ON event(actor_id, causal_sequence);',
    );

    await db.execute('''
      CREATE VIEW next_actor_sequence AS
      SELECT actor_id, COALESCE(MAX(actor_sequence), 0) + 1 AS next_seq
      FROM event
      GROUP BY actor_id;
    ''');

    await db.execute('''
      CREATE VIEW next_causal_sequence AS
      SELECT actor_id, COALESCE(MAX(causal_sequence), 0) + 1 AS next_seq
      FROM event
      GROUP BY actor_id;
    ''');

    await db.execute('''
      CREATE VIEW next_local_sequence AS
      SELECT COALESCE(MAX(local_sequence), 0) + 1 AS next_seq
      FROM event;
    ''');
  }

  Future<void> insertEvent(int actorId) => db.execute(
    '''
    INSERT INTO event (actor_id, actor_sequence, causal_sequence, local_sequence)
    VALUES (
      ?,
      COALESCE((SELECT next_seq FROM next_actor_sequence WHERE actor_id = ?), 1),
      COALESCE((SELECT next_seq FROM next_causal_sequence WHERE actor_id = ?), 1),
      (SELECT next_seq FROM next_local_sequence)
    );
  ''',
    [actorId, actorId, actorId],
  );

  Future<List<int>> actorSequences(int actorId) async {
    final rows = await db.query(
      'SELECT actor_sequence FROM event WHERE actor_id = ? ORDER BY actor_sequence',
      [actorId],
    );
    return [for (final r in rows) r[0] as int];
  }

  Future<List<int>> causalSequences(int actorId) async {
    final rows = await db.query(
      'SELECT causal_sequence FROM event WHERE actor_id = ? ORDER BY causal_sequence',
      [actorId],
    );
    return [for (final r in rows) r[0] as int];
  }

  Future<List<int>> localSequences() async {
    final rows = await db.query(
      'SELECT local_sequence FROM event ORDER BY local_sequence',
    );
    return [for (final r in rows) r[0] as int];
  }
}

void main() {
  late CausalDb causal;

  setUp(() async {
    causal = CausalDb(IsolateSqlite());
    await causal.db.openInMemory();
    await causal.setup();
  });

  tearDown(() async {
    await causal.db.close();
  });

  test('actor_sequence increments per actor', () async {
    await causal.insertEvent(1); // 1
    await causal.insertEvent(1); // 2
    await causal.insertEvent(2); // 1

    expect(await causal.actorSequences(1), [1, 2]);
    expect(await causal.actorSequences(2), [1]);
  });

  test('causal_sequence increments per actor', () async {
    await causal.insertEvent(1); // 1
    await causal.insertEvent(1); // 2
    await causal.insertEvent(2); // 1

    expect(await causal.causalSequences(1), [1, 2]);
    expect(await causal.causalSequences(2), [1]);
  });

  test('local_sequence increments globally', () async {
    await causal.insertEvent(1); // 1
    await causal.insertEvent(1); // 2
    await causal.insertEvent(2); // 3

    expect(await causal.localSequences(), [1, 2, 3]);
  });

  test('failed insert does not consume sequences', () async {
    await causal.insertEvent(1); // local 1, actor 1, causal 1
    await causal.insertEvent(1); // local 2, actor 2, causal 2

    expect(
      () => causal.db.execute(
        'INSERT INTO event (actor_id, actor_sequence, causal_sequence, local_sequence) VALUES (NULL, 1, 1, 99)',
      ),
      throwsException,
    );

    await causal.insertEvent(1); // local 3, actor 3, causal 3
    expect(await causal.actorSequences(1), [1, 2, 3]);
    expect(await causal.causalSequences(1), [1, 2, 3]);
    expect(await causal.localSequences(), [1, 2, 3]);
  });

  test('primary key is local_sequence', () async {
    await causal.insertEvent(1); // local 1

    expect(
      () => causal.db.execute(
        'INSERT INTO event (actor_id, actor_sequence, causal_sequence, local_sequence) VALUES (?, ?, ?, ?)',
        [1, 99, 99, 1],
      ),
      throwsException,
    );
  });
}
