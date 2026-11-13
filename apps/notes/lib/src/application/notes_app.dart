import 'dart:math';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes_app/src/projection/note_list_projection.dart';
import 'package:notes_app/src/projection/note_projection.dart';
import 'package:notes_app/src/command/create_note.dart';
import 'package:notes_app/src/command/restore_note.dart';
import 'package:notes_app/src/command/trash_note.dart';
import 'package:notes_app/src/command/update_note_content.dart';
import 'package:notes_app/src/command/update_note_title.dart';
import 'package:notes_app/src/command/test_simulate_external_note_content_append.dart';
import 'package:notes_app/src/command/test_simulate_external_note_content_random_insert.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:notes_app/src/projection/search.dart';
import 'package:notes_app/src/projection/statistics_projection.dart';

/// Exposes note commands and projection queries over a supplied [CqrsRuntime].
class NotesApp {
  final NoteCommands command;
  late final NoteQueries query;
  final IdGenerator _idGenerator;
  late final String actor;

  late final LiveProjection<SearchModel, NoteEvent> _searchProjection;

  /// [searchRuntime] defaults to [cqrsRuntime] and must use the same event store.
  NotesApp({
    required CqrsRuntime cqrsRuntime,
    CqrsRuntime? searchRuntime,
    required Fts fts,
    required Logger logger,
    IdGenerator? idGenerator,
  }) : _idGenerator = idGenerator ?? IdGeneratorRandom(),
       command = NoteCommands(cqrsRuntime, logger) {
    searchRuntime ??= cqrsRuntime;
    for (final runtime in {cqrsRuntime, searchRuntime}) {
      runtime.eventRegistry
        ..add(const NoteContentUpdatedCodec())
        ..add(const NoteCreatedCodec())
        ..add(const NoteRestoredCodec())
        ..add(const NoteTitleUpdatedCodec())
        ..add(const NoteTrashedCodec());
    }
    actor = cqrsRuntime.actor;
    _searchProjection = searchRuntime.liveProjection(SearchProjection(fts));
    query = NoteQueries(cqrsRuntime, searchProjection: _searchProjection);
  }

  /// Allocates an identifier before a note is persisted.
  String generateNoteId() => _idGenerator.generateId();

  /// Starts projections and completes after initial catch-up.
  Future<void> startProjections() => _searchProjection.latest();

  /// Completes when projections stop, or fails after a projection failure.
  Future<void> get projectionsDone => _searchProjection.done;

  /// Stops projections and waits for active work to finish.
  Future<void> stopProjections() => _searchProjection.stop();
}

/// Writes note events through the runtime.
class NoteCommands {
  final CqrsRuntime _runtime;
  final Logger _logger;
  final Random _random = Random();

  NoteCommands(this._runtime, this._logger);

  Future<void> createNote(String noteId) =>
      _runtime.execute(CreateNote(noteId: noteId, logger: _logger));

  Future<void> updateNoteTitle(String noteId, String value) => _runtime.execute(
    UpdateNoteTitle(noteId: noteId, fullValue: value, logger: _logger),
  );

  Future<void> updateNoteContent(String noteId, CrdtTextChange change) =>
      _runtime.execute(
        UpdateNoteContent(noteId: noteId, change: change, logger: _logger),
      );

  Future<void> trashNote(String noteId) =>
      _runtime.execute(TrashNote(noteId: noteId));

  Future<void> restoreNote(String noteId) =>
      _runtime.execute(RestoreNote(noteId: noteId));

  /// Appends text as another writer against the command's resolved state.
  Future<void> testSimulateExternalNoteContentAppend(
    String noteId,
    String text, {
    required String actorId,
  }) async {
    if (actorId == _runtime.actor) {
      throw ArgumentError('Simulation requires a distinct actor');
    }
    await _runtime.execute(
      TestSimulateExternalNoteContentAppend(
        noteId: noteId,
        text: text,
        actorId: actorId,
      ),
    );
  }

  /// Inserts configurable text at a random position for visual testing.
  Future<void> testSimulateExternalNoteContentRandomInsert(
    String noteId,
    String text, {
    required String actorId,
  }) async {
    if (actorId == _runtime.actor) {
      throw ArgumentError('Simulation requires a distinct actor');
    }
    await _runtime.execute(
      TestSimulateExternalNoteContentRandomInsert(
        noteId: noteId,
        text: text,
        actorId: actorId,
        random: _random,
      ),
    );
  }
}

/// Resolves current note state directly from the event history.
class NoteQueries {
  final CqrsRuntime _runtime;
  final LiveProjection<SearchModel, NoteEvent> _searchProjection;
  final _noteListProjection = NoteListProjection();
  final _statisticsProjection = StatisticsProjection();

  NoteQueries(this._runtime, {required this._searchProjection});

  /// Creates an unstarted note projection owned by the caller.
  LiveProjection<NoteModel, NoteEvent> liveNote(String noteId) =>
      _runtime.liveProjection(NoteProjection(noteId));

  /// Creates an unstarted list projection owned by the caller.
  LiveProjection<NoteListModel, NoteEvent> liveNoteList() =>
      _runtime.liveProjection(_noteListProjection);

  /// Waits for search to apply all notified changes.
  Future<void> get searchReady => _searchProjection.latest();

  Future<List<NoteModel>> noteSearch(String text) async {
    final model = await _searchProjection.latest();
    final ids = await model.search(text, resultCount: 20);
    final states = await Future.wait(
      ids.map((id) => _runtime.resolveProjection(NoteProjection(id))),
    );

    return states;
  }

  Future<StatisticsModel> statistics() =>
      _runtime.resolveProjection(_statisticsProjection);
}
