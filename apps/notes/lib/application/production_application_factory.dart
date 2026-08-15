import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/application.dart';
import 'package:notes/application/application_factory.dart';
import 'package:notes/repo/note/sqlite_note_projection_repo.dart';
import 'package:notes/repo/note/sqlite_resolved_note_repo.dart';
import 'package:notes/repo/search/sqlite_search_repo.dart';
import 'package:notes/runtime/notes_runtime.dart';
import 'package:path_provider/path_provider.dart';

class ProductionApplicationFactory implements ApplicationFactory {
  static Future<String> getSupportDir() async {
    // on linux it is
    // /home/{USER}/.local/share/com.claudare.notes
    final appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    return appDir.path;
  }

  @override
  Application create() {
    final IdGenerator idGenerator = IdGeneratorSecure();
    final timeProvider = SystemTimeProvider();
    final logger = ConsoleLogger(name: 'notes', minimumLevel: LogLevel.debug);

    final sqliteDb = IsolateSqlite();
    final eventStore = EventStore(SqliteEventDatabase(sqliteDb));
    final runtimeRepo = SqliteRuntimeRepo(sqliteDb);

    final cqrsDependencies = CqrsRuntimeDependencies(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
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
        cqrsDependencies: cqrsDependencies,
        noteProjectionRepo: noteProjectionRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
        searchProjectionRepo: searchProjectionRepo,
        searchReadModel: searchReadModel,
      ),
    );
  }
}
