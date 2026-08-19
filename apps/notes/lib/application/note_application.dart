import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/event/note.dart';
import 'package:notes/projection/note_projection.dart';
import 'package:notes/projection/search_projection.dart';
import 'package:notes/read_model/composite_note_search.dart';
import 'package:notes/read_model/note/resolved_note_read_model.dart';
import 'package:notes/read_model/note/sqlite_note_database.dart';
import 'package:notes/read_model/search/search_read_model.dart';
import 'package:notes/read_model/search/sqlite_search_database.dart';
import 'package:time_provider/time_provider.dart';

class NoteApplication {
  late final IsolateSqlite _sqliteDb;
  late final IsolateSqlite _searchDb;

  late final EventStore eventStore;
  final Logger logger;
  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  late final ResolvedNoteReadModel resolvedNoteReadModel;
  late final SearchReadModel searchReadModel;
  late final CompositeNoteSearch compositeNoteSearch;

  late final CqrsRuntime _cqrsRuntime;

  NoteApplication({
    required this.idGenerator,
    required this.timeProvider,
    required this.logger,
  }) {
    _sqliteDb = IsolateSqlite();
    eventStore = EventStore(SqliteEventDatabase(_sqliteDb));

    final cqrsDependencies = CqrsRuntimeDependencies(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
      eventStore: eventStore,
      runtimeDatabase: SqliteRuntimeDatabase(_sqliteDb),
    );

    final noteDatabase = SqliteNoteDatabase(_sqliteDb);
    resolvedNoteReadModel = noteDatabase;

    _searchDb = IsolateSqlite();
    final searchDatabase = SqliteSearchDatabase(_searchDb);
    searchReadModel = searchDatabase;

    final projectionRegistry =
        ProjectionRegistry()
          ..add(NoteProjection(noteDatabase))
          ..add(SearchProjection(searchDatabase, logger));

    final eventRegistry =
        EventRegistry()
          ..add(const NoteContentUpdatedCodec())
          ..add(const NoteCreatedCodec())
          ..add(const NoteRestoredCodec())
          ..add(const NoteTitleUpdatedCodec())
          ..add(const NoteTrashedCodec());

    _cqrsRuntime = CqrsRuntime(
      dependencies: cqrsDependencies,
      eventRegistry: eventRegistry,
      projectionRegistry: projectionRegistry,
      runtimeName: 'notes',
    );

    compositeNoteSearch = CompositeNoteSearch(
      resolvedNoteReadModel,
      searchReadModel,
    );
  }

  NoteApplication.test({
    IdGenerator? idGenerator,
    TimeProvider? timeProvider,
    Logger? logger,
  }) : this(
         idGenerator: idGenerator ?? IdGeneratorSequential(),
         timeProvider: timeProvider ?? FakeTimeProviderStatic.zero(),
         logger: logger ?? const NoopLogger(),
       );

  Future<void> commandExecute<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) => _cqrsRuntime.executeCommand(command, input);

  Future<void> initialize({
    required String notesDbFilepath,
    required String searchDbFilepath,
  }) async {
    logger.debug('main database path: $notesDbFilepath');
    await _sqliteDb.open(notesDbFilepath);
    await _searchDb.open(searchDbFilepath);

    await eventStore.migrate();
    await _cqrsRuntime.initializeProjections();
  }

  Future<void> close() async {
    await _sqliteDb.close();
    await _searchDb.close();
  }

  Future<void> recreateProjections() => _cqrsRuntime.recreateProjections();

  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }

  @override
  int get hashCode => identityHashCode(this);
}
