import 'dart:io';

import 'package:notes/application/note_bootstrap.dart';
import 'package:path/path.dart' as path;
import 'package:restart_app/restart_app.dart';

/// Deletes all local Notes data and requests a process restart.
Future<void> resetAndRestartNotes(
  NoteBootstrap bootstrap,
  Future<String> Function() applicationDirectory,
) async {
  final directory = await applicationDirectory();
  await resetDatabase(bootstrap, path.join(directory, 'main.sqlite'));
  await Restart.restartApp(mode: RestartMode.process);
}

/// Closes Notes and removes its database and SQLite sidecars.
Future<void> resetDatabase(NoteBootstrap bootstrap, String filepath) async {
  await bootstrap.close();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$filepath$suffix');
    if (file.existsSync()) file.deleteSync();
  }
}
