import 'package:isolate_sqlite/src/sync_context.dart';

import 'isolate_sqlite.dart';

typedef MigrationFn = void Function(SyncContext tx);

/// A synchronous database change identified by [version].
class SqliteMigration {
  final int version;
  final MigrationFn up;

  // TODO: make up a named paramter
  const SqliteMigration(this.version, this.up);
}

// TODO: option to disable foreign key constraints?
/// Applies migrations in declaration order within one transaction.
class SqliteMigrations {
  final String _migrationTable;
  final List<SqliteMigration> _migrations = [];

  SqliteMigrations({required this._migrationTable});

  /// Adds the next consecutive migration, starting at version zero.
  /// Throws [ArgumentError] when [migration] has another version.
  void add(SqliteMigration migration) {
    if (migration.version != _migrations.length) {
      throw ArgumentError.value(
        migration.version,
        'migration.version',
        'Expected migration version ${_migrations.length}',
      );
    }
    _migrations.add(migration);
  }

  // TODO: increase maximum lock time on the database, as migrations could be long!
  /// Applies pending migrations and records them in the same transaction.
  /// Throws [StateError] if an applied version is no longer defined.
  Future<void> migrate(IsolateSqlite db) async {
    final migrations = List<SqliteMigration>.of(_migrations);
    final migrationTable = _migrationTable;
    await db.transaction((tx) {
      tx.execute('''
        CREATE TABLE IF NOT EXISTS $migrationTable (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        )
      ''');

      final applied = tx.query(
        'SELECT version FROM $migrationTable ORDER BY version',
      );
      final appliedSet = applied.map((r) => r[0] as int).toSet();

      for (final version in appliedSet) {
        if (version < 0 || version >= migrations.length) {
          throw StateError(
            'Applied migration version $version in $migrationTable is not '
            'defined. Only ${migrations.length} migrations are defined.',
          );
        }
      }

      for (final m in migrations) {
        if (appliedSet.contains(m.version)) continue;

        m.up(tx);
        tx.execute(
          'INSERT INTO $migrationTable (version, applied_at) VALUES (?, CURRENT_TIMESTAMP)',
          [m.version],
        );
      }
    });
  }
}
