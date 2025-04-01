import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

abstract class DatabaseBase {
  late SqliteDatabase db;
  String _path;

  DatabaseBase(this._path) : db = SqliteDatabase(path: _path);

  DatabaseBase.temporary() : _path = '' {
    final tempDir = _getTempDir();
    _path = '$tempDir/db';
    db = SqliteDatabase(path: _path);
  }

  Future<void> deinit() async {
    await db.close();
  }
}

Future<int> databaseGetSizeBytes(DatabaseBase anyDb) async {
  final path = anyDb._path;
  final bytes = await File(path).length();
  return bytes;
}

Future<void> databaseDELETE(DatabaseBase anyDb) async {
  await _deleteDbFiles(anyDb._path);
}

String _getTempDir() {
  final tempDir = Directory.systemTemp.path;
  return Directory(tempDir).createTempSync('sqlite_db_').path;
}

// Future<void> _tempDirCleanup(String tempDir) async {
//   // check that this dir is in Directory.systemTemp.path
//   if (!tempDir.startsWith(Directory.systemTemp.path)) {
//     throw Exception('Attempted to cleanup db not in a temporary directory!!!');
//   }

//   await Directory(tempDir).delete(recursive: true);
// }

// https://github.com/powersync-ja/sqlite_async.dart/discussions/13
// https://github.com/powersync-ja/sqlite_async.dart/blob/d937c5d6d2b1ee4f22a2e14311d614f869087e5b/test/util.dart#L89-L97
Future<void> _deleteDbFiles(String path) async {
  try {
    await File(path).delete();
  } on PathNotFoundException {
    // Not an issue
  }
  try {
    await File("$path-shm").delete();
  } on PathNotFoundException {
    // Not an issue
  }
  try {
    await File("$path-wal").delete();
  } on PathNotFoundException {
    // Not an issue
  }
}
