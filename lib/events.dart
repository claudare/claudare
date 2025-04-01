import 'package:notes_app_v0/common.dart';

sealed class NoteEvent {
  const NoteEvent();
}

class NoteCreated extends NoteEvent {
  final Id id;

  const NoteCreated(this.id);

  @override
  String toString() => 'NoteCreated(id: $id)';
}

class NoteContentUpdated extends NoteEvent {
  final Id id;
  final String content;

  const NoteContentUpdated(this.id, this.content);

  @override
  String toString() => 'NoteContentUpdated(id: $id, content: $content)';
}

class NoteTitleUpdated extends NoteEvent {
  final Id id;
  final String title;

  const NoteTitleUpdated(this.id, this.title);

  @override
  String toString() => 'NoteTitleUpdated(id: $id, title: $title)';
}

class NoteDeleted extends NoteEvent {
  final Id id;

  const NoteDeleted(this.id);

  @override
  String toString() => 'NoteDeleted(id: $id)';
}

class NoteMoved extends NoteEvent {
  final Id id;
  final int toIndex;

  const NoteMoved(this.id, this.toIndex);

  @override
  String toString() => 'NoteMoved(id: $id, toIndex: $toIndex)';
}

// tag events

class TagAssigned extends NoteEvent {
  final Id noteId;
  final String tagName;

  const TagAssigned(this.noteId, this.tagName);

  @override
  String toString() => 'TagAssigned(noteId: $noteId, tag: $tagName)';
}

class TagUnassigned extends NoteEvent {
  final Id noteId;
  final String tagName;

  const TagUnassigned(this.noteId, this.tagName);

  @override
  String toString() => 'TagUnassigned(noteId: $noteId, tag: $tagName)';
}
