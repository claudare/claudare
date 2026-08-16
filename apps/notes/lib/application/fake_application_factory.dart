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
  final NotesRuntime? mockNotesRuntime;
  final IdGenerator? mockIdGenerator;
  final TimeProvider? mockTimeProvider;
  final Logger? mockLogger;
  final MigrationPolicy migrationPolicy;

  FakeApplicationFactory({
    this.mockNotesRuntime,
    this.mockIdGenerator,
    this.mockTimeProvider,
    this.mockLogger,
    this.migrationPolicy = MigrationPolicy.whenVersionChanges,
  });

  @override
  Application create() {
    final IdGenerator idGenerator = mockIdGenerator ?? IdGeneratorSequential();
    final timeProvider = mockTimeProvider ?? FakeTimeProviderStatic.zero();
    final logger = mockLogger ?? const NoopLogger();

    final sqliteDb = IsolateSqlite();
    final eventStore = EventStore(SqliteEventDatabase(sqliteDb));
    final runtimeDatabase = SqliteRuntimeDatabase(sqliteDb);

    final cqrsDependencies = CqrsRuntimeDependencies(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
      eventStore: eventStore,
      runtimeDatabase: runtimeDatabase,
    );

    final noteProjectionRepo = SqliteNoteProjectionRepo(sqliteDb);
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
        cqrsDependencies: cqrsDependencies,
        noteProjectionRepo: noteProjectionRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
        searchProjectionRepo: searchProjectionRepo,
        searchReadModel: searchReadModel,
        migrationPolicy: migrationPolicy,
      ),
    );
  }
}
