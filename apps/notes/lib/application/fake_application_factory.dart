import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/application.dart';
import 'package:notes/repo/note/sqlite_resolved_note_repo.dart';
import 'package:notes/repo/search/sqlite_search_repo.dart';
import 'package:notes/runtime/notes_runtime.dart';

import '../repo/note/sqlite_note_projection_repo.dart';
import 'application_factory.dart';

class FakeApplicationFactory implements ApplicationFactory {
  // TODO: mocking somehow?
  final NotesRuntime? mockNotesRuntime;
  final IdGenerator? mockIdGenerator;
  final TimeProvider? mockTimeProvider;
  final Logger? mockLogger;

  FakeApplicationFactory({
    this.mockNotesRuntime,
    this.mockIdGenerator,
    this.mockTimeProvider,
    this.mockLogger,
  });

  @override
  Application create() {
    final IdGenerator idGenerator = mockIdGenerator ?? IdGeneratorSequential();
    final timeProvider = mockTimeProvider ?? FakeTimeProviderStatic.zero();
    final logger = mockLogger ?? const NoopLogger();

    final sqliteDb = IsolateSqlite();
    final eventStore = SqliteEventStore(sqliteDb);
    final runtimeRepo = SqliteRuntimeRepo(sqliteDb);

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
      eventStorePageSize: 20,
      eventStore: eventStore,
      runtimeRepo: runtimeRepo,
    );

    final noteProjectionRepo = SqliteNoteProjectionRepo(sqliteDb, logger);
    final resolvedNoteReadModel = SqliteResolvedNoteReadModel(sqliteDb);

    final searchDb = IsolateSqlite();

    final searchProjectionRepo = SqliteSearchRepo(searchDb);
    final searchReadModel = SqliteSearchRepo(searchDb);

    return Application(
      sqliteDb: sqliteDb,
      searchDb: searchDb,
      eventStore: eventStore,
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      notesRuntime: NotesRuntime(
        cqrsConfig: cqrsConfig,
        noteProjectionRepo: noteProjectionRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
        searchProjectionRepo: searchProjectionRepo,
        searchReadModel: searchReadModel,
      ),
    );
  }
}
