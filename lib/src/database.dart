import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

abstract class DatabaseBase {
  late SqliteDatabase db;
  String? _tempDir;

  DatabaseBase(String path) : db = SqliteDatabase(path: path);

  DatabaseBase.temporary() {
    _tempDir = _getTempDir();
    final path = '$_tempDir/db';
    db = SqliteDatabase(path: path);
  }

  Future<void> deinit() async {
    await db.close();

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
