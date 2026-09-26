import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_string.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Details obtained by replaying one note stream.
class NoteState {
  final String noteId;
  bool exists = false;
  final CrdtString _title = CrdtString();
  final CrdtText _content = CrdtText();
  late DateTime createdAt;
  late DateTime updatedAt;
  DateTime? trashedAt;

  NoteState(this.noteId);

  String get title => _title.value;
  String get content => _content.text;

  /// Persisted content state for initializing an independent editing context.
  CrdtText get contentDocument => _content;
  bool get isTrashed => trashedAt != null;

  void apply(EventEnvelope<NoteEvent> envelope) {
    final actor = envelope.actor;
    final occuredAt = envelope.occuredAt;

    switch (envelope.event) {
      case NoteCreated():
        exists = true;
        createdAt = occuredAt;
        updatedAt = occuredAt;
        trashedAt = null;
      case NoteTitleUpdated(:final newTitle):
        _requireCreated();
        _title.applyChange(
          CrdtStringChange(value: newTitle, actor: actor, time: occuredAt),
        );
        updatedAt = occuredAt;
      case NoteContentUpdated(:final change):
        _requireCreated();
        _content.applyChange(change);
        updatedAt = occuredAt;
      case NoteTrashed():
        _requireCreated();
        trashedAt = occuredAt;
      case NoteRestored():
        _requireCreated();
        trashedAt = null;
    }
  }

  void _requireCreated() {
    if (!exists) {
      throw StateError('note $noteId was not created');
    }
  }
}

/// Replays events for one note without retaining a snapshot.
class NoteAggregate implements Aggregate<NoteEvent, NoteState> {
  final String noteId;

  const NoteAggregate(this.noteId);

  @override
  Snapshotter<NoteState>? get snapshotter => null;

  @override
  int get version => 1;

  @override
  StreamRoute get streamRoute => noteStreamRoute;

  @override
  NoteState initialState() => NoteState(noteId);

  @override
  bool canApply(EventEnvelope<NoteEvent> envelope) =>
      envelope.event.noteId == noteId;

  @override
  void apply(NoteState state, EventEnvelope<NoteEvent> envelope) {
    state.apply(envelope);
  }
}
