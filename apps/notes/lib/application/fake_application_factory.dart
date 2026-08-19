import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/application.dart';
import 'package:notes/read_model/note/sqlite_note_database.dart';
import 'package:notes/read_model/search/sqlite_search_database.dart';

import 'application_factory.dart';

class FakeApplicationFactory implements ApplicationFactory {
  final IdGenerator? mockIdGenerator;
  final TimeProvider? mockTimeProvider;
  final Logger? mockLogger;

  FakeApplicationFactory({
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
