import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_string.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Details obtained by replaying one note stream.
class NoteState implements AggregateState<NoteEvent> {
  final String noteId;
  bool exists = false;
  final CrdtString _title;
  final CrdtText _content;
  late DateTime createdAt;
  late DateTime updatedAt;
  DateTime? trashedAt;

  NoteState(this.noteId, {CrdtText? contentDocument})
    : _title = CrdtString(),
      _content = contentDocument ?? CrdtText();

  NoteState._copy(this.noteId, this._title, this._content);

  /// Returns independent state with the same resolved note history.
  NoteState clone() {
    final copy = NoteState._copy(
      noteId,
      CrdtString.fromJson(_title.toJson()),
      _content.fork(),
    );
    copy.exists = exists;
    if (exists) {
      copy.createdAt = createdAt;
      copy.updatedAt = updatedAt;
    }
    copy.trashedAt = trashedAt;
    return copy;
  }

  String get title => _title.value;
  String get content => _content.text;

  /// Persisted content state observed by attached editing contexts.
  CrdtText get contentDocument => _content;
  bool get isTrashed => trashedAt != null;

  @override
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

Aggregate<NoteEvent, NoteState> noteAggregate(
  String noteId, {
  CrdtText? contentDocument,
}) => Aggregate(
  name: 'Note $noteId',
  filter: PatternFilter.exact(noteStreamRoute.buildPath(noteId)),
  state: NoteState(noteId, contentDocument: contentDocument),
);
