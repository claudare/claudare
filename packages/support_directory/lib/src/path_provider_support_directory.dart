import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'support_directory.dart';

/// Resolves namespaced directories through [getApplicationSupportDirectory].
class PathProviderSupportDirectory implements SupportDirectory {
  final String _namespace;
  final Future<Directory> Function() _resolveBaseDirectory;

  PathProviderSupportDirectory({
    required String namespace,
    Future<Directory> Function()? resolveBaseDirectory,
  }) : _namespace = namespace,
       _resolveBaseDirectory =
           resolveBaseDirectory ?? getApplicationSupportDirectory {
    if (namespace.isEmpty || RegExp(r'[^a-zA-Z0-9_-]').hasMatch(namespace)) {
      throw ArgumentError.value(namespace, 'namespace', 'Invalid namespace');
    }
  }

  Future<Directory> _resolve() async {
    final base = await _resolveBaseDirectory();
    return Directory(path.join(base.path, _namespace));
  }

  @override
  Future<Directory> getDirectory() async {
    final directory = await _resolve();
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
    final directory = await _resolve();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
