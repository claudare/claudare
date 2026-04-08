import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application/application.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_internal_repo.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_read_model.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';

import 'application_factory.dart';

class TestApplicationFactory implements ApplicationFactory {
  // TODO: mocking somehow?
  final NotesRuntime? mockNotesRuntime;
  final IdGenerator? mockIdGenerator;
  final TimeProvider? mockTimeProvider;

  TestApplicationFactory({
    this.mockNotesRuntime,
    this.mockIdGenerator,
    this.mockTimeProvider,
  });

  @override
  Future<Application> create() async {
    final idGenerator = mockIdGenerator ?? FakeIdGeneratorSequential();
    final timeProvider = mockTimeProvider ?? FakeTimeProviderStatic.zero();

    final cqrsConfig = CqrsRuntimeConfig(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      eventStorePageSize: 20,
    );

    final sqliteDb = IsolateSqlite(IsolateSqlite.memoryInitFn);
    final eventStore = SqliteEventStore(sqliteDb);

    final noteInternalRepo = SqliteNoteInternalRepo(sqliteDb);
    final noteReadModel = SqliteNoteReadModel(sqliteDb);

    return Application(
      sqliteDb: sqliteDb,
      eventStore: eventStore,
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      notesRuntime:
          mockNotesRuntime ??
          NotesRuntime(
            eventStore: eventStore,
            cqrsConfig: cqrsConfig,
            noteInternalRepo: noteInternalRepo,
            noteReadModel: noteReadModel,
          ),
    );
  }
}
