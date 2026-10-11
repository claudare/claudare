import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'support_directory.dart';

/// Manages the directory returned by [getApplicationSupportDirectory].
class PathProviderSupportDirectory implements SupportDirectory {
  @override
  Future<Directory> getDirectory() async {
    final directory = await getApplicationSupportDirectory();
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
    final directory = await getApplicationSupportDirectory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
