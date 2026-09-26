import 'dart:math';

import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:id_generator/id_generator.dart';
import 'package:mutex/mutex.dart' show Mutex;
import 'package:notes/aggregate/note.dart';
import 'package:notes/aggregate/note_list.dart';
import 'package:notes/aggregate/statistics.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/restore_note.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/command/test_simulate_external_note_content_append.dart';
import 'package:notes/command/test_simulate_external_note_content_random_insert.dart';
import 'package:notes/event/note.dart';

export 'package:notes/aggregate/note.dart' show NoteState;
export 'package:notes/aggregate/note_list.dart'
    show NoteCategory, NoteListState, NoteSortOrder;

/// Exposes note commands and aggregate queries over a supplied [CqrsRuntime].
class NoteApplication {
  final NoteCommands command;
  final NoteQueries query;
  final IdGenerator _idGenerator;

  late final String actor;

  NoteApplication({required CqrsRuntime cqrsRuntime, IdGenerator? idGenerator})
    : _idGenerator = idGenerator ?? IdGeneratorSecure(),
      command = NoteCommands(cqrsRuntime),
      query = NoteQueries(cqrsRuntime) {
    cqrsRuntime.eventRegistry
      ..add(const NoteContentUpdatedCodec())
      ..add(const NoteCreatedCodec())
      ..add(const NoteRestoredCodec())
      ..add(const NoteTitleUpdatedCodec())
      ..add(const NoteTrashedCodec())
      ..freeze();
    actor = cqrsRuntime.actor;
  }

  /// Allocates an identifier before a note is persisted.
  String generateNoteId() => _idGenerator.generateId();
}

/// Writes note events through the runtime.
class NoteCommands {
  final CqrsRuntime _runtime;
  final Random _random = Random();

  NoteCommands(this._runtime);

  Future<void> createNote(String noteId) =>
      _runtime.execute(CreateNote(noteId: noteId));

  Future<void> updateNoteTitle(String noteId, String value) =>
      _runtime.execute(UpdateNoteTitle(noteId: noteId, fullValue: value));

  Future<void> updateNoteContent(String noteId, CrdtTextChange change) =>
      _runtime.execute(UpdateNoteContent(noteId: noteId, change: change));

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
  final _noteList = noteListAggregate();
  final _noteListMutex = Mutex();

  NoteQueries(this._runtime);

  /// Returns the resolved state for one note identifier.
  Future<NoteState> note(String noteId) =>
      (_runtime.resolve(noteAggregate(noteId))).then((v) => v.state);

  Future<void> catchupNote(Aggregate<NoteEvent, NoteState> aggregate) async {
    await _runtime.resolve(aggregate);
  }

  /// Returns sorted references to notes in the cached aggregate.
  /// A later catchup can update the returned [NoteState] objects.
  Future<List<NoteState>> noteList({
    NoteCategory category = NoteCategory.active,
    NoteSortOrder order = NoteSortOrder.createdAtDescending,
  }) {
    return _noteListMutex.protect(() async {
      await _runtime.resolve(_noteList);
      return _noteList.state.toSortedList(category: category, order: order);
    });
  }

  Future<StatisticsState> statistics() async {
    final v = await _runtime.resolve(statisticsAggregate());
    return v.state;
  }
}
