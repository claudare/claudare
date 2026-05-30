import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application/application.dart';
import 'package:notes_app_v0/application/application_factory.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_projection_repo.dart';
import 'package:notes_app_v0/repo/note/sqlite_resolved_note_repo.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:path_provider/path_provider.dart';

class ProductionApplicationFactory implements ApplicationFactory {
  static Future<String> getSupportDir() async {
    // on linux it is
    // /home/{USER}/.local/share/com.example.notes_app_v0
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
