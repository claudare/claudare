import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_string.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

/// Reconstructs one note from its event stream.
class NoteProjection implements Projection<NoteModel, NoteEvent> {
  final String _noteId;

  @override
  String get name => 'full-note-state-$_noteId';

  @override
  LogFilter get filter => noteStreamFilter(_noteId);

  const NoteProjection(this._noteId);

  @override
  ProjectionLoad<NoteModel> load() =>
      ProjectionLoad.initial(NoteModel._(_noteId));

  @override
  void apply(NoteModel model, EventEnvelope<NoteEvent> envelope) {
    final actor = envelope.actor;
    final occuredAt = envelope.occuredAt;

    switch (envelope.event) {
      case NoteCreated():
        model.exists = true;
        model.isDeleted = false;
        model.createdAt = occuredAt;
        model.updatedAt = occuredAt;
        model.trashedAt = null;
      case NoteTitleUpdated(:final newTitle):
        _requireCreated(model);
        model._title.applyChange(
          CrdtStringChange(value: newTitle, actor: actor, time: occuredAt),
        );
        model.updatedAt = occuredAt;
      case NoteContentUpdated(:final change):
        _requireCreated(model);
        model._content.applyChange(change);
        model.updatedAt = occuredAt;
      case NoteTrashed():
        _requireCreated(model);
        model.trashedAt = occuredAt;
      case NoteRestored():
        _requireCreated(model);
        model.trashedAt = null;
    }
  }

  @override
  void onStreamDeleted(NoteModel model, StreamDeletion deletion) {
    model._title = CrdtString();
    model._content = CrdtText();
    model.exists = false;
    model.isDeleted = true;
    model.createdAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    model.updatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    model.trashedAt = null;
  }

  void _requireCreated(NoteModel model) {
    if (!model.exists) {
      throw StateError('note $_noteId was not created');
    }
  }
}

/// Mutable note data maintained by [NoteProjection].
class NoteModel {
  final String noteId;
  bool exists = false;
  bool isDeleted = false;
  CrdtString _title = CrdtString();
  CrdtText _content = CrdtText();
  DateTime createdAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime? trashedAt;

  NoteModel._(this.noteId);

  String get title => _title.value;
  String get content => _content.text;

  /// Persisted title state observed by attached editing contexts.
  CrdtString get titleDocument => _title;

  /// Persisted content state observed by attached editing contexts.
  CrdtText get contentDocument => _content;
  bool get isTrashed => trashedAt != null;
}
