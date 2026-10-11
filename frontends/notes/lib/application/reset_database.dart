import 'package:notes/application/note_bootstrap.dart';
import 'package:restart_app/restart_app.dart';
import 'package:support_directory/support_directory.dart';

/// Deletes all local Notes data and optionally requests a process restart.
Future<void> resetApplication(
  NoteBootstrap bootstrap,
  SupportDirectory supportDirectory, {
  required bool restart,
}) async {
  await bootstrap.close();
  await supportDirectory.delete();
  if (restart) {
    await Restart.restartApp(mode: RestartMode.process);
  }
}
