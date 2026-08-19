import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/application.dart';
import 'package:notes/application/application_factory.dart';
import 'package:notes/read_model/note/sqlite_note_database.dart';
import 'package:notes/read_model/search/sqlite_search_database.dart';
import 'package:path_provider/path_provider.dart';

class ProductionApplicationFactory implements ApplicationFactory {
  const ProductionApplicationFactory();

  static Future<String> getSupportDir() async {
    // on linux it is
    // ~/.local/share/com.claudare.notes
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
    final runtimeDatabase = SqliteRuntimeDatabase(sqliteDb);

    final cqrsDependencies = CqrsRuntimeDependencies(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
      eventStore: eventStore,
      runtimeDatabase: runtimeDatabase,
    );

    final noteDatabase = SqliteNoteDatabase(sqliteDb);

    final searchDb = IsolateSqlite();

    final searchDatabase = SqliteSearchDatabase(searchDb);

    return Application(
      sqliteDb: sqliteDb,
      searchDb: searchDb,
      cqrsDependencies: cqrsDependencies,
      noteDatabase: noteDatabase,
      searchDatabase: searchDatabase,
    );
  }
}
