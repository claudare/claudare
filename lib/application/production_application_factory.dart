import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application/application.dart';
import 'package:notes_app_v0/application/application_factory.dart';
import 'package:notes_app_v0/read_model/internal_note/internal_note_read_model_sqlite.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model_sqlite.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_internal_repo.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:path/path.dart' as path show join;
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
  Application create(String supportDir) {
    final idGenerator = RandomIdGenerator();
    final timeProvider = SystemTimeProvider();

    // print('opening production database at $filename');
    final sqliteDb = IsolateSqlite(() {
      final filename = path.join(supportDir, 'notes.db');

      print('using database at $filename');
      final db = sqlite3.open(filename);

      IsolateSqlite.enableOptimizations(db);

      return db;
    });
    final eventStore = SqliteEventStore(sqliteDb);
    final runtimeRepo = SqliteRuntimeRepo(sqliteDb);

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      eventStorePageSize: 20,
      eventStore: eventStore,
      runtimeRepo: runtimeRepo,
    );

    final noteInternalRepo = SqliteNoteInternalRepo(sqliteDb);
    final resolvedNoteReadModel = ResolvedNoteReadModelSqlite(sqliteDb);
    final internalNoteReadModel = InternalNoteReadModelSqlite(sqliteDb);

    return Application(
      sqliteDb: sqliteDb,
      eventStore: eventStore,
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      notesRuntime: NotesRuntime(
        cqrsConfig: cqrsConfig,
        noteInternalRepo: noteInternalRepo,
        resolvedNoteReadModel: resolvedNoteReadModel,
        internalNoteReadModel: internalNoteReadModel,
      ),
    );
  }
}
