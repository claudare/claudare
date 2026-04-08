import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application/application.dart';
import 'package:notes_app_v0/application/application_factory.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_internal_repo.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_read_model.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:path/path.dart' as path show join;
import 'package:path_provider/path_provider.dart';

class ProductionApplicationFactory implements ApplicationFactory {
  static Future<String> _getDatabasePath() async {
    // on linux it is
    // /home/{USER}/.local/share/com.example.notes_app_v0
    final appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    return path.join(appDir.path, 'notes.db');
  }

  @override
  Future<Application> create() async {
    final idGenerator = RandomIdGenerator();
    final timeProvider = SystemTimeProvider();

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      eventStorePageSize: 20,
    );

    print('preparing to open db path');

    // final sqliteDb = IsolateSqlite(IsolateSqlite.memoryInitFn);
    final filename = await _getDatabasePath();

    print('opening production database at $filename');
    final sqliteDb = IsolateSqlite(() {
      print('INSIDE INIT FILENAME $filename');
      final db = sqlite3.open(filename);

      IsolateSqlite.enableOptimizations(db);

      return db;
    });
    final eventStore = SqliteEventStore(sqliteDb);

    final noteInternalRepo = SqliteNoteInternalRepo(sqliteDb);
    final noteReadModel = SqliteNoteReadModel(sqliteDb);

    return Application(
      sqliteDb: sqliteDb,
      eventStore: eventStore,
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      notesRuntime: NotesRuntime(
        eventStore: eventStore,
        cqrsConfig: cqrsConfig,
        noteInternalRepo: noteInternalRepo,
        noteReadModel: noteReadModel,
      ),
    );
  }
}
