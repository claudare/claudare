import 'dart:io';

import 'package:path/path.dart' as path;

import 'support_directory.dart';

/// Owns a randomly named system temporary directory for isolated tests.
class TempSupportDirectory implements SupportDirectory {
  Future<Directory>? _directory;

  @override
  Future<Directory> getDirectory() async {
    final directory = await (_directory ??= Directory.systemTemp.createTemp(
      'claudare-support-',
    ));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String> getFilePath(String filename) async {
    final directory = await getDirectory();
    return path.join(directory.path, filename);
  }

  @override
  Future<void> delete() async {
    final pending = _directory;
    if (pending == null) return;
    final directory = await pending;
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
