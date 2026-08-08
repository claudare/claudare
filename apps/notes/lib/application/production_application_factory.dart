import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
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
    final idGenerator = RandomIdGenerator();
    final timeProvider = SystemTimeProvider();

    final sqliteDb = IsolateSqlite();
    final eventStore = SqliteEventStore(sqliteDb);
    final runtimeRepo = SqliteRuntimeRepo(sqliteDb);

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: const NoopLogger(),
      eventStorePageSize: 20,
      eventStore: eventStore,
      runtimeRepo: runtimeRepo,
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
        cqrsConfig: cqrsConfig,
        noteProjectionRepo: noteProjectionRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
        searchProjectionRepo: searchProjectionRepo,
        searchReadModel: searchReadModel,
      ),
    );
  }
}
