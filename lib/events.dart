import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:messagepack/messagepack.dart';

sealed class NoteEvent {
  const NoteEvent();

  void pack(Packer p);
  NoteEvent.fromJson(Map<String, dynamic> json);

  static final Map<String, NoteEvent Function(Unpacker)> _parsers = {
    NoteCreated._type: NoteCreated.unpack,
    NoteContentUpdated._type: NoteContentUpdated.unpack,
    NoteTitleUpdated._type: NoteTitleUpdated.unpack,
    NoteDeleted._type: NoteDeleted.unpack,
    NoteMoved._type: NoteMoved.unpack,
    TagAssigned._type: TagAssigned.unpack,
    TagUnassigned._type: TagUnassigned.unpack,
  };

  static NoteEvent unpackBytes(Uint8List bytes) {
    final u = Unpacker(bytes);

    final type = u.unpackString()!;

    if (!_parsers.containsKey(type)) {
      throw Exception('Unknown note event type $type');
    }

    return _parsers[type]!(u);
  }
}

class NoteCreated extends NoteEvent {
  static const _type = 'note_created';
  final GenericId id;

  const NoteCreated(this.id);

  @override
  void pack(Packer p) {
    p.packString(_type);
    id.pack(p);
  }

  NoteCreated.unpack(Unpacker u) : id = GenericId.unpack(u);

  @override
  String toString() => 'NoteCreated(id: $id)';
}

class NoteContentUpdated extends NoteEvent {
  static const _type = 'note_content_updated';
  final GenericId id;
  final String content;

  const NoteContentUpdated(this.id, this.content);

  @override
  void pack(Packer p) {
    p.packString(_type);
    id.pack(p);
    p.packString(content);
  }

  NoteContentUpdated.unpack(Unpacker u)
    : id = GenericId.unpack(u),
      content = u.unpackString()!;

  @override
  String toString() => 'NoteContentUpdated(id: $id, content: $content)';
}

class NoteTitleUpdated extends NoteEvent {
  static const _type = 'note_title_updated';
  final GenericId id;
  final String title;

  const NoteTitleUpdated(this.id, this.title);

  @override
  void pack(Packer p) {
    p.packString(_type);
    id.pack(p);
    p.packString(title);
  }

  NoteTitleUpdated.unpack(Unpacker u)
    : id = GenericId.unpack(u),
      title = u.unpackString()!;

  @override
  String toString() => 'NoteTitleUpdated(id: $id, title: $title)';
}

class NoteDeleted extends NoteEvent {
  static const _type = 'note_deleted';
  final GenericId id;

  const NoteDeleted(this.id);

  @override
  void pack(Packer p) {
    id.pack(p);
  }

  NoteDeleted.unpack(Unpacker u) : id = GenericId.unpack(u);

  @override
  String toString() => 'NoteDeleted(id: $id)';
}

class NoteMoved extends NoteEvent {
  static const _type = 'note_moved';
  final GenericId id;
  final int toIndex;

  const NoteMoved(this.id, this.toIndex);

  @override
  void pack(Packer p) {
    p.packString(_type);
    id.pack(p);
    p.packInt(toIndex);
  }

  NoteMoved.unpack(Unpacker u)
    : id = GenericId.unpack(u),
      toIndex = u.unpackInt()!;

  @override
  String toString() => 'NoteMoved(id: $id, toIndex: $toIndex)';
}

class TagAssigned extends NoteEvent {
  static const _type = 'tag_assigned';
  final GenericId noteId;
  final String tagName;

  const TagAssigned(this.noteId, this.tagName);

  @override
  void pack(Packer p) {
    p.packString(_type);
    noteId.pack(p);
    p.packString(tagName);
  }

  TagAssigned.unpack(Unpacker u)
    : noteId = GenericId.unpack(u),
      tagName = u.unpackString()!;

  @override
  String toString() => 'TagAssigned(noteId: $noteId, tag: $tagName)';
}

class TagUnassigned extends NoteEvent {
  static const _type = 'tag_unassigned';
  final GenericId noteId;
  final String tagName;

  const TagUnassigned(this.noteId, this.tagName);

  @override
  void pack(Packer p) {
    p.packString(_type);
    noteId.pack(p);
    p.packString(tagName);
  }

  TagUnassigned.unpack(Unpacker u)
    : noteId = GenericId.unpack(u),
      tagName = u.unpackString()!;

  @override
  String toString() => 'TagUnassigned(noteId: $noteId, tag: $tagName)';
}
