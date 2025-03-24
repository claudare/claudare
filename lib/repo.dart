// this is a virtual database that stores notes with thier content and
// also stores their order
// this uses no flutter things, only dart code

import 'dart:async';

import 'package:notes_app_v0/common.dart';

const _previewLength = 100;

class NoteData {
  final Id id;

  // dont mutate these directly please
  String title;
  String content;
  Set<String> _tags;

  DateTime createdAt;
  DateTime updatedAt;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  // make unnamed paramters
  NoteData(
    this.id,
    this.title,
    this.content,
    this._tags,
    this.createdAt,
    this.updatedAt,
  );

  // getters
  String getPreviewContent() {
    return content.length > _previewLength
        ? content.substring(0, _previewLength)
        : content;
  }

  NoteData.emptyNew(this.id, DateTime time)
    : title = '',
      content = '',
      _tags = {},
      createdAt = time,
      updatedAt = time;

  List<String> get tags => _tags.toList()..sort();

  // mutators below
  void updateTitle(String value, DateTime timestamp) {
    title = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  void updateContent(String value, DateTime timestamp) {
    content = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  void addTag(String tag, DateTime timestamp) {
    _tags.add(tag);
    updatedAt = timestamp;
    _notifyChange();
  }

  void removeTag(String tag, DateTime timestamp) {
    _tags.remove(tag);
    updatedAt = timestamp;
    _notifyChange();
  }

  void _notifyChange() {
    // snapshot wiriting to the database could happen here
    // the NoteData class should have a reference to the storage.
    _changeController.add(null);
  }

  void dispose() {
    _changeController.close();
  }
}

class NoteOrderData {
  final List<Id> _order;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  NoteOrderData(this._order);

  List<Id> get items => _order;

  void add(Id id) {
    // add to the beginning, this list is upside down
    _order.insert(0, id);
    _notifyChange();
  }

  void moveToIndex(Id id, int index) {
    final current = _order.indexOf(id);

    if (current == -1) throw ArgumentError('Note not found $id');
    if (current == index) throw ArgumentError('Note already at index $index');

    _order.removeAt(current);
    _order.insert(index, id);

    _notifyChange();
  }

  void remove(Id id) {
    _order.remove(id);
    _notifyChange();
  }

  void _notifyChange() {
    _changeController.add(null);
  }

  void dispose() {
    _changeController.close();
  }
}

class TagsData {
  // association of tags to notes
  final Map<String, List<Id>> _tags;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  TagsData(this._tags);

  void addTag(Id noteId, String tagName) {
    _tags[tagName] ??= [];
    _tags[tagName]!.add(noteId);

    _notifyChange();
  }

  void removeTag(Id noteId, String tagName) {
    final list = _tags[tagName];
    if (list == null) {
      throw Exception('Tag $tagName not found');
    }

    list.remove(noteId);
    if (list.isEmpty) {
      _tags.remove(tagName);
    }

    _notifyChange();
  }

  // get all tags sorted alphabetically
  List<String> get values => _tags.keys.toList()..sort();

  List<Id> getTagNodeIds(String tag) => _tags[tag] ?? [];

  void _notifyChange() {
    // snapshot wiriting to the database could happen here
    // the NoteData class should have a reference to the storage.
    _changeController.add(null);
  }

  void dispose() {
    _changeController.close();
  }
}

// this is like the full state of the application, but without flutter things.
// Managed by dispatching events
class Repo {
  final Map<Id, NoteData> _notes;
  final NoteOrderData _order;
  final TagsData _tags;

  Repo(this._notes, this._order, this._tags);

  Repo.empty() : _notes = {}, _order = NoteOrderData([]), _tags = TagsData({});

  // Access methods that return the reactive objects
  NoteData? getNote(Id id) => _notes[id];
  NoteOrderData get order => _order;
  TagsData get tags => _tags;

  void dispose() {
    _order.dispose();
    _tags.dispose();
    for (final note in _notes.values) {
      note.dispose();
    }
  }

  // Method for creating a new note
  void processEvent(NoteEvent event, DateTime timestamp) {
    // writing of event to db should happen here
    print('Processing event: $event');
    switch (event) {
      case NoteCreated event:
        // saving of note and order can happen here
        _notes[event.id] = NoteData.emptyNew(event.id, timestamp);
        _order.add(event.id);
        break;
      case NoteContentUpdated event:
        final note = _notes[event.id]!;
        note.updateContent(event.content, timestamp);
        break;
      case NoteTitleUpdated event:
        final note = _notes[event.id]!;
        note.updateTitle(event.title, timestamp);
        break;
      case NoteDeleted event:
        final note = _notes.remove(event.id);
        note?.dispose();
        _order.remove(event.id);
        break;
      case NoteMoved event:
        _order.moveToIndex(event.id, event.toIndex);
        break;
      case TagAssigned event:
        final note = _notes[event.noteId]!;
        note.addTag(event.tagName, timestamp);
        tags.addTag(event.noteId, event.tagName);
        break;
      case TagUnassigned event:
        final note = _notes[event.noteId]!;
        note.removeTag(event.tagName, timestamp);
        tags.removeTag(event.noteId, event.tagName);
        break;
    }
  }
}

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
