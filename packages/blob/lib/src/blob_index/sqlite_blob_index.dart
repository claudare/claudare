import 'package:isolate_sqlite/isolate_sqlite.dart';

import 'blob_index.dart';

final _blobIndexMigrations =
    SqliteMigrations(migrationTable: 'migrations_blob_index')..add(
      SqliteMigration(0, (tx) {
        tx.execute('''CREATE TABLE blob_index(
          id TEXT PRIMARY KEY NOT NULL,
          status INTEGER NOT NULL
        );''');
      }),
    );

/// Indexes blob metadata in an injected SQLite database.
class SqliteBlobIndex implements BlobIndex {
  final IsolateSqlite _database;

  SqliteBlobIndex(IsolateSqlite database) : _database = database;

  /// Creates or migrates the blob metadata schema before use.
  Future<void> migrate() => _blobIndexMigrations.migrate(_database);

  /// Closes the supplied database after its consumers have stopped.
  Future<void> close() => _database.close();

  @override
  Future<BlobMetadata> get(String blobId) async {
    final row = await _database.queryRow(
      'SELECT status FROM blob_index WHERE id = ?;',
      [blobId],
    );
    if (row == null) {
      return BlobMetadata(blobId: blobId, status: BlobStatus.missing);
    }
    final status = BlobStatus.values[row.field<int>('status')];
    return BlobMetadata(blobId: blobId, status: status);
  }

  @override
  Future<void> upsert(BlobMetadata metadata) => _database.execute(
    '''INSERT INTO blob_index(id, status)
    VALUES (?, ?)
    ON CONFLICT(id)
      DO UPDATE SET status = excluded.status;''',
    [metadata.blobId, metadata.status.index],
  );
}
