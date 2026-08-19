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
  final IsolateSqlite _sqliteDb;
  final IsolateSqlite _searchDb;

  final EventStore eventStore;
  final Logger logger;
  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  final ResolvedNoteReadModel resolvedNoteReadModel;
  final SearchReadModel searchReadModel;
  late final CompositeNoteSearch compositeNoteSearch;

  late final CqrsRuntime _cqrsRuntime;

  NoteApplication({
    required IsolateSqlite sqliteDb,
    required IsolateSqlite searchDb,
    required CqrsRuntimeDependencies cqrsDependencies,
    required SqliteNoteDatabase noteDatabase,
    required SqliteSearchDatabase searchDatabase,
  }) : _searchDb = searchDb,
       _sqliteDb = sqliteDb,
       eventStore = cqrsDependencies.eventStore,
       logger = cqrsDependencies.logger,
       idGenerator = cqrsDependencies.idGenerator,
       timeProvider = cqrsDependencies.timeProvider,
       resolvedNoteReadModel = noteDatabase,
       searchReadModel = searchDatabase {
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
