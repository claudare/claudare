import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:notes_app/notes_app.dart';
import 'package:time_provider/time_provider.dart';

/// Adds a remote title command using only the Notes public API.
Future<void> addRemoteTitleUpdate(
  MemoryEventStore store,
  String noteId,
  String title,
) async {
  final remoteStore = MemoryEventStore();
  final lastPosition = (await store.getState()).lastCommandLogPosition;
  final ids = await store.getNextCommandIds(
    CommandDependency(),
    (lastPosition ?? -1) + 1,
  );
  for (final id in ids) {
    final command = await store.getStoredCommand(id);
    if (!await remoteStore.addStoredCommand(command!)) {
      throw StateError('Could not copy note history');
    }
  }

  final remote = NotesApp(
    cqrsRuntime: CqrsRuntime(
      eventStore: remoteStore,
      actor: 'remote',
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic(DateTime.utc(2026)),
    ),
  );
  await remote.command.updateNoteTitle(noteId, title);
  final command = await remoteStore.getStoredCommand(
    const CommandId('remote', 1),
  );
  if (!await store.addStoredCommand(command!)) {
    throw StateError('Could not deliver remote note update');
  }
}
