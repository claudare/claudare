import 'package:core/cqrs.dart';
import 'package:common/common.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/restore_note.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/projection/note/note_projection.dart';
import 'package:notes/projection/note/note_projection_repo.dart';
import 'package:notes/projection/search/search_projection.dart';
import 'package:notes/projection/search/search_projection_repo.dart';
import 'package:notes/read_model/composite_note_search.dart';
import 'package:notes/read_model/resolved_note/resolved_note_read_model.dart';
import 'package:notes/read_model/search/search_read_model.dart';

class NotesRuntime {
  static int runtimeVersion = 7;

  // the read model is exposed directly
  final NoteProjectionRepo _noteProjectionRepo;
  final SearchProjectionRepo _searchProjectionRepo;

  final ResolvedNoteReadModel resolvedNoteReadModel;
  final SearchReadModel searchReadModel;
  final Logger logger;

  late final CqrsRuntime _cqrsRuntime;
  late final CqrsCommands commands;

  late final CompositeNoteSearch compositeNoteSearch;
  Function(Object error)? _onFatalError;

  NotesRuntime({
    required CqrsRuntimeConfig cqrsConfig,
    required NoteProjectionRepo noteProjectionRepo,
    required this.resolvedNoteReadModel,
    required SearchProjectionRepo searchProjectionRepo,
    required this.searchReadModel,
  }) : logger = cqrsConfig.logger,
       _noteProjectionRepo = noteProjectionRepo,
       _searchProjectionRepo = searchProjectionRepo {
    // where does the deviceId come from?
    // does it come during the init phase or fetched automatically inside the CqrsRuntime?

    // this is an error handler that transitions the app into a "fatal state"
    final fatalErrorHandler = StandardProjectionFailureHandler(
      notifyFn: (e) {
        if (_onFatalError == null) {
          throw StateError(
            'allpcation fatal error not handled, as it is not set: ${e.error}',
          );
        }

        _onFatalError!(e.error);
      },
    );

    // technically search can use a different error handler.
    // Failure in search projection should just disable search functionality.
    // This is too much for now though

    final noteProjection = NoteProjection(
      _noteProjectionRepo,
      fatalErrorHandler,
    );
    final searchProjection = SearchProjection(
      _searchProjectionRepo,
      fatalErrorHandler,
      logger,
    );

    _cqrsRuntime = CqrsRuntime(
      config: cqrsConfig,
      projectors: [noteProjection, searchProjection],
      thisDeviceId: DeviceId.unassigned(),
      runtimeName: 'notes',
      runtimeVersion: NotesRuntime.runtimeVersion,
    );

    commands = CqrsCommands(
      createNote: _cqrsRuntime.bindCommand(CreateNote(logger), [
        noteProjection,
      ]),
      trashNote: _cqrsRuntime.bindCommand(TrashNote(), [noteProjection]),
      restoreNote: _cqrsRuntime.bindCommand(RestoreNote(), [noteProjection]),
      updateNoteContent: _cqrsRuntime.bindCommand(UpdateNoteContent(logger), [
        noteProjection,
      ]),
      updateNoteTitle: _cqrsRuntime.bindCommand(UpdateNoteTitle(logger), [
        noteProjection,
      ]),
    );

    compositeNoteSearch = CompositeNoteSearch(
      resolvedNoteReadModel,
      searchReadModel,
    );
  }

  TimeProvider get timeProvider => _cqrsRuntime.timeProvider;
  IdGenerator get idGenerator => _cqrsRuntime.idGenerator;

  void setFatalErrorHandler(Function(Object error) handler) {
    _onFatalError = handler;
  }

  Future<void> initialize() async {
    await _cqrsRuntime.initializeProjections();
  }

  Future<void> rerunProjections() async {
    await _cqrsRuntime.rerunProjections();
  }

  // commands can be implemented like this too? need to keep projections on top level
  // BoundCommand<CreateNoteInput> get createNoteCommand =>
  //     _cqrsRuntime.bindCommand(CreateNote(), []);
}

class CqrsCommands {
  final BoundCommand<CreateNoteInput> createNote;
  final BoundCommand<TrashNoteInput> trashNote;
  final BoundCommand<RestoreNoteInput> restoreNote;
  final BoundCommand<UpdateNoteContentInput> updateNoteContent;
  final BoundCommand<UpdateNoteTitleInput> updateNoteTitle;

  const CqrsCommands({
    required this.createNote,
    required this.trashNote,
    required this.restoreNote,
    required this.updateNoteContent,
    required this.updateNoteTitle,
  });
}
