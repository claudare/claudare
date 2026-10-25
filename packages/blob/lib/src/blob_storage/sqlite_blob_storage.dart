import 'dart:typed_data';

import 'package:isolate_sqlite/isolate_sqlite.dart';

import 'blob_storage.dart';

final _blobStorageMigrations =
    SqliteMigrations(migrationTable: 'migrations_blob_storage')..add(
      SqliteMigration(0, (tx) {
        tx.execute('''CREATE TABLE blob_storage(
          id TEXT PRIMARY KEY NOT NULL,
          data BLOB NOT NULL
        );''');
      }),
    );

/// Stores immutable blob bytes in an injected SQLite database.
class SqliteBlobStorage implements BlobStorage {
  final IsolateSqlite _database;

  SqliteBlobStorage(IsolateSqlite database) : _database = database;

  /// Creates or migrates the blob schema before use.
  Future<void> migrate() => _blobStorageMigrations.migrate(_database);

  /// Closes the supplied database after its consumers have stopped.
  Future<void> close() => _database.close();

  @override
  Future<Uint8List?> get(String blobId) => _database.transaction((tx) {
    final row = tx.queryRow('SELECT data FROM blob_storage WHERE id = ?;', [
      blobId,
    ]);
    return row?.field<Uint8List>('data');
  });

  @override
  Future<void> save(String blobId, Uint8List data) => _database.transaction((
    tx,
  ) {
    final row = tx.queryRow('SELECT data FROM blob_storage WHERE id = ?;', [
      blobId,
    ]);
    if (row != null) {
      final existing = row.field<Uint8List>('data');
      if (existing.length != data.length) {
        throw StateError('Blob already contains different bytes: $blobId');
      }
      for (var index = 0; index < data.length; index++) {
        if (existing[index] != data[index]) {
          throw StateError('Blob already contains different bytes: $blobId');
        }
      }
      return;
    }
    tx.execute('INSERT INTO blob_storage(id, data) VALUES (?, ?);', [
      blobId,
      data,
    ]);
  });
}
