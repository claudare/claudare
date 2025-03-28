import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

class Database {
  late SqliteDatabase underlyingDb;
  String? _tempDir;

  Database(String path) : underlyingDb = SqliteDatabase(path: path);

  Database.temporary() {
    _tempDir = _getTempDir();
    final path = '$_tempDir/db';
    underlyingDb = SqliteDatabase(path: path);
  }

  Database.fromSqliteDatabase(this.underlyingDb);

  Future<void> deinit() async {
    await underlyingDb.close();

    if (_tempDir != null) {
      await _tempDirCleanup(_tempDir!);
    }
  }
}

//https://github.com/powersync-ja/sqlite_async.dart/discussions/13
String _getTempDir() {
  final tempDir = Directory.systemTemp.path;
  return Directory(tempDir).createTempSync('sqlite_db_').path;
}

Future<void> _tempDirCleanup(String tempDir) async {
  // check that this dir is in Directory.systemTemp.path
  if (!tempDir.startsWith(Directory.systemTemp.path)) {
    throw Exception('Attempted to cleanup db not in a temporary directory!!!');
  }

  await Directory(tempDir).delete(recursive: true);
}
