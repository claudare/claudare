import 'package:core/core.dart';

sealed class NoteEvent {
  const NoteEvent();

  Map<String, dynamic> toJson();
  NoteEvent.fromJson(Map<String, dynamic> json);

  static final Map<String, NoteEvent Function(Map<String, dynamic>)> _parsers =
      {
        NoteCreated._type: (json) => NoteCreated.fromJson(json),
        NoteContentUpdated._type: (json) => NoteContentUpdated.fromJson(json),
        NoteTitleUpdated._type: (json) => NoteTitleUpdated.fromJson(json),
        NoteDeleted._type: (json) => NoteDeleted.fromJson(json),
        NoteMoved._type: (json) => NoteMoved.fromJson(json),
        TagAssigned._type: (json) => TagAssigned.fromJson(json),
        TagUnassigned._type: (json) => TagUnassigned.fromJson(json),
      };

  static NoteEvent anyFromJson(Map<String, dynamic> json) {
    if (_parsers.containsKey(json['_type'])) {
      return _parsers[json['_type']]!(json);
    }
    throw Exception('Unknown note event type: ${json['_type']}');
  }
}

class NoteCreated extends NoteEvent {
  static const _type = 'note_created';
  final GenericId id;

  const NoteCreated(this.id);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'id': id.toString()};
  }

  factory NoteCreated.fromJson(Map<String, dynamic> json) {
    return NoteCreated(GenericId.fromString(json['id']));
  }

  @override
  String toString() => 'NoteCreated(id: $id)';
}

class NoteContentUpdated extends NoteEvent {
  static const _type = 'note_content_updated';
  final GenericId id;
  final String content;

  const NoteContentUpdated(this.id, this.content);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'id': id.toString(), 'content': content};
  }

  factory NoteContentUpdated.fromJson(Map<String, dynamic> json) {
    return NoteContentUpdated(
      GenericId.fromString(json['id']),
      json['content'],
    );
  }

  @override
  String toString() => 'NoteContentUpdated(id: $id, content: $content)';
}

class NoteTitleUpdated extends NoteEvent {
  static const _type = 'note_title_updated';
  final GenericId id;
  final String title;

  const NoteTitleUpdated(this.id, this.title);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'id': id.toString(), 'title': title};
  }

  factory NoteTitleUpdated.fromJson(Map<String, dynamic> json) {
    return NoteTitleUpdated(GenericId.fromString(json['id']), json['title']);
  }

  @override
  String toString() => 'NoteTitleUpdated(id: $id, title: $title)';
}

class NoteDeleted extends NoteEvent {
  static const _type = 'note_deleted';
  final GenericId id;

  const NoteDeleted(this.id);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'id': id.toString()};
  }

  factory NoteDeleted.fromJson(Map<String, dynamic> json) {
    return NoteDeleted(GenericId.fromString(json['id']));
  }

  @override
  String toString() => 'NoteDeleted(id: $id)';
}

class NoteMoved extends NoteEvent {
  static const _type = 'note_moved';
  final GenericId id;
  final int toIndex;

  const NoteMoved(this.id, this.toIndex);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'id': id.toString(), 'toIndex': toIndex};
  }

  factory NoteMoved.fromJson(Map<String, dynamic> json) {
    return NoteMoved(GenericId.fromString(json['id']), json['toIndex']);
  }

  @override
  String toString() => 'NoteMoved(id: $id, toIndex: $toIndex)';
}

class TagAssigned extends NoteEvent {
  static const _type = 'tag_assigned';
  final GenericId noteId;
  final String tagName;

  const TagAssigned(this.noteId, this.tagName);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'noteId': noteId.toString(), 'tagName': tagName};
  }

  factory TagAssigned.fromJson(Map<String, dynamic> json) {
    return TagAssigned(GenericId.fromString(json['noteId']), json['tagName']);
  }

  @override
  String toString() => 'TagAssigned(noteId: $noteId, tag: $tagName)';
}

class TagUnassigned extends NoteEvent {
  static const _type = 'tag_unassigned';
  final GenericId noteId;
  final String tagName;

  const TagUnassigned(this.noteId, this.tagName);

  @override
  Map<String, dynamic> toJson() {
    return {'_type': _type, 'noteId': noteId.toString(), 'tagName': tagName};
  }

  factory TagUnassigned.fromJson(Map<String, dynamic> json) {
    return TagUnassigned(GenericId.fromString(json['noteId']), json['tagName']);
  }

  @override
  String toString() => 'TagUnassigned(noteId: $noteId, tag: $tagName)';
}
