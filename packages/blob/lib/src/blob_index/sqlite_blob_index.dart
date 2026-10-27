import 'package:isolate_sqlite/isolate_sqlite.dart';

import 'blob_index.dart';

final _blobIndexMigrations =
    SqliteMigrations(migrationTable: 'migrations_blob_index')..add(
      SqliteMigration(0, (tx) {
        tx.execute('''CREATE TABLE blob_index(
          id TEXT PRIMARY KEY NOT NULL
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
      'SELECT id FROM blob_index WHERE id = ?;',
      [blobId],
    );
    if (row == null) {
      return BlobMetadata(blobId: blobId, status: BlobStatus.missing);
    }
    return BlobMetadata(blobId: blobId, status: BlobStatus.available);
  }

  @override
  Future<void> markAvailable(String blobId) => _database.execute(
    '''INSERT INTO blob_index(id)
    VALUES (?)
    ON CONFLICT(id) DO NOTHING;''',
    [blobId],
  );
}
