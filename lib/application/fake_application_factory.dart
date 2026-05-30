import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application/application.dart';
import 'package:notes_app_v0/repo/note/sqlite_resolved_note_repo.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';

import '../repo/note/sqlite_note_projection_repo.dart';
import 'application_factory.dart';

class FakeApplicationFactory implements ApplicationFactory {
  // TODO: mocking somehow?
  final NotesRuntime? mockNotesRuntime;
  final IdGenerator? mockIdGenerator;
  final TimeProvider? mockTimeProvider;

  FakeApplicationFactory({
    this.mockNotesRuntime,
    this.mockIdGenerator,
    this.mockTimeProvider,
  });

  @override
  Application create() {
    final idGenerator = mockIdGenerator ?? FakeIdGeneratorSequential();
    final timeProvider = mockTimeProvider ?? FakeTimeProviderStatic.zero();

    final sqliteDb = IsolateSqlite();
    final eventStore = SqliteEventStore(sqliteDb);
    final runtimeRepo = SqliteRuntimeRepo(sqliteDb);

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      eventStorePageSize: 20,
      eventStore: eventStore,
      runtimeRepo: runtimeRepo,
    );

    final noteProjectionRepo = SqliteNoteProjectionRepo(sqliteDb);
    final resolvedNoteReadModel = SqliteResolvedNoteReadModel(sqliteDb);

    return Application(
      sqliteDb: sqliteDb,
      eventStore: eventStore,
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      notesRuntime: NotesRuntime(
        cqrsConfig: cqrsConfig,
        noteProjectionRepo: noteProjectionRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
      ),
    );
  }
}
