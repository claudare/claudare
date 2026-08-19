import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:notes/event/note.dart';
import 'package:notes/projection/note_projection.dart';
import 'package:notes/projection/search_projection.dart';
import 'package:notes/read_model/composite_note_search.dart';
import 'package:notes/read_model/note/note_projection_repo.dart';
import 'package:notes/read_model/note/resolved_note_read_model.dart';
import 'package:notes/read_model/search/search_projection_repo.dart';
import 'package:notes/read_model/search/search_read_model.dart';

class NotesRuntime {
  // the read model is exposed directly
  final NoteProjectionRepo _noteProjectionRepo;
  final SearchProjectionRepo _searchProjectionRepo;

  final ResolvedNoteReadModel resolvedNoteReadModel;
  final SearchReadModel searchReadModel;
  final Logger logger;

  late final CqrsRuntime _cqrsRuntime;

  late final CompositeNoteSearch compositeNoteSearch;

  NotesRuntime({
    required CqrsRuntimeDependencies cqrsDependencies,
    required NoteProjectionRepo noteProjectionRepo,
    required this.resolvedNoteReadModel,
    required SearchProjectionRepo searchProjectionRepo,
    required this.searchReadModel,
  }) : logger = cqrsDependencies.logger,
       _noteProjectionRepo = noteProjectionRepo,
       _searchProjectionRepo = searchProjectionRepo {
    final noteProjection = NoteProjection(_noteProjectionRepo);
    final searchProjection = SearchProjection(_searchProjectionRepo, logger);
    final projectionRegistry =
        ProjectionRegistry()
          ..add(noteProjection)
          ..add(searchProjection);

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

  TimeProvider get timeProvider => _cqrsRuntime.timeProvider;
  IdGenerator get idGenerator => _cqrsRuntime.idGenerator;

  Future<void> initialize() async {
    await _cqrsRuntime.initializeProjections();
  }

  Future<void> recreateProjections() async {
    await _cqrsRuntime.recreateProjections();
  }

  Future<void> executeCommand<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) => _cqrsRuntime.executeCommand(command, input);
}
