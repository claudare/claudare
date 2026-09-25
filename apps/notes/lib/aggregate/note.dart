import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Details obtained by replaying one note stream.
class NoteState {
  final String noteId;
  bool exists = false;
  CrdtValueLatestWriteWins<String> _title =
      CrdtValueLatestWriteWins<String>.zero('');
  String content = '';
  late DateTime createdAt;
  late DateTime updatedAt;
  DateTime? trashedAt;

  NoteState(this.noteId);

  String get title => _title.value;
  bool get isTrashed => trashedAt != null;

  void apply(NoteEvent event, DateTime occuredAt) {
    switch (event) {
      case NoteCreated():
        exists = true;
        _title = CrdtValueLatestWriteWins('', occuredAt);
        content = '';
        createdAt = occuredAt;
        updatedAt = occuredAt;
        trashedAt = null;
      case NoteTitleUpdated(:final newTitle):
        _requireCreated();
        _title = _title.merge(newTitle, occuredAt);
        updatedAt = occuredAt;
      case NoteContentUpdated(:final newContent):
        _requireCreated();
        content = newContent;
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
    state.apply(envelope.event, envelope.occuredAt);
  }
}
