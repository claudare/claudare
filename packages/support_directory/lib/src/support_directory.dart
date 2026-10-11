import 'dart:io';

/// Manages a directory for application support files.
abstract interface class SupportDirectory {
  /// Returns the owned directory, creating it recursively if needed.
  Future<Directory> getDirectory();

  /// Returns the path for [filename], creating the directory but not the file.
  Future<String> getFilePath(String filename);

  /// Deletes the owned directory and its contents; absence is a no-op.
  ///
  /// Close resources using this directory before deleting it.
  Future<void> delete();
}
