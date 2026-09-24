import 'dart:io';

import 'package:notes/application/note_bootstrap.dart';
import 'package:path/path.dart' as path;
import 'package:restart_app/restart_app.dart';

/// Deletes local event history and requests a process restart.
Future<void> resetAndRestartNotes(
  NoteBootstrap bootstrap,
  Future<String> Function() applicationDirectory,
) async {
  final directory = await applicationDirectory();
  await resetEventDatabase(bootstrap, path.join(directory, 'events.sqlite'));
  await Restart.restartApp(mode: RestartMode.process);
}

/// Closes Notes and removes its event database and SQLite sidecars.
Future<void> resetEventDatabase(
  NoteBootstrap bootstrap,
  String filepath,
) async {
  await bootstrap.close();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$filepath$suffix');
    if (file.existsSync()) file.deleteSync();
  }
}
