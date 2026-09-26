import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes/aggregate/note.dart';
import 'package:notes/aggregate/note_list.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/restore_note.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

export 'package:notes/aggregate/note.dart' show NoteState;
export 'package:notes/aggregate/note_list.dart'
    show NoteCategory, NoteListState, NoteSortOrder;

/// Exposes note commands and aggregate queries over a supplied [CqrsRuntime].
class NoteApplication {
  final NoteCommands command;
  final NoteQueries query;

  late final String actor;

  NoteApplication({required CqrsRuntime cqrsRuntime})
    : command = NoteCommands(cqrsRuntime),
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
}

/// Writes note events through the runtime.
class NoteCommands {
  final CqrsRuntime _runtime;
  final IdGenerator _idGenerator = IdGeneratorSecure();

  NoteCommands(this._runtime);

  Future<String> createNote() async {
    final noteId = _idGenerator.generateId();
    await _runtime.execute(CreateNote(noteId: noteId));
    return noteId;
  }

  Future<void> updateNoteTitle(String noteId, String value) =>
      _runtime.execute(UpdateNoteTitle(noteId: noteId, fullValue: value));

  Future<void> updateNoteContent(String noteId, CrdtTextChange change) =>
      _runtime.execute(UpdateNoteContent(noteId: noteId, change: change));

  Future<void> trashNote(String noteId) =>
      _runtime.execute(TrashNote(noteId: noteId));

  Future<void> restoreNote(String noteId) =>
      _runtime.execute(RestoreNote(noteId: noteId));

  /// Simulates another writer against the persisted note content.
  Future<void> simulateExternalNoteContentEdit(
    String noteId,
    String newText, {
    required String actorId,
  }) async {
    if (actorId == _runtime.actor) {
      throw ArgumentError('Simulation requires a distinct actor');
    }
    final note = await _runtime.resolve(NoteAggregate(noteId));
    if (!note.exists) throw Exception('Note not found');
    final context = CrdtTextEditContext(
      document: note.contentDocument,
      actorId: actorId,
    );
    updateText(context, newText);
    final change = context.prepareChange();
    if (change != null) await updateNoteContent(noteId, change);
  }
}

/// Resolves current note state directly from the event history.
class NoteQueries {
  final CqrsRuntime _runtime;

  const NoteQueries(this._runtime);

  /// Reads note events from the inclusive [fromVersion] until caught up.
  Stream<({int version, EventEnvelope<NoteEvent> envelope})> noteEvents(
    String noteId, {
    int fromVersion = 0,
  }) async* {
    final reader = _runtime.streamReader(
      noteStreamRoute.buildPath(noteId),
      fromVersion: fromVersion,
    );
    await for (final stored in reader.scan()) {
      yield (
        version: stored.version,
        envelope: EventEnvelope<NoteEvent>(
          actor: stored.eventId.actor,
          streamPath: stored.streamPath,
          event: _runtime.eventRegistry.decode<NoteEvent>(stored.encodedEvent),
          occuredAt: stored.occuredAt,
        ),
      );
    }
  }

  Future<NoteState?> note(String noteId) async {
    final state = await _runtime.resolve(NoteAggregate(noteId));
    return state.exists ? state : null;
  }

  Future<NoteListState> noteList() =>
      _runtime.resolve(const NoteListAggregate());
}
