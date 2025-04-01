// this is a virtual database that stores notes with thier content and
// also stores their order
// this uses no flutter things, only dart code

import 'dart:async';

import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:notes_app_v0/events.dart';

const _previewLength = 100;

class NoteData {
  final GenericId id;

  String title;
  String content;
  final Set<String> _tags;

  Timestamp createdAt;
  Timestamp updatedAt;

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

  NoteData.emptyNew(this.id)
    : title = '',
      content = '',
      _tags = {},
      createdAt = id.timestamp,
      updatedAt = id.timestamp;

  List<String> get tags => _tags.toList()..sort();

  // mutators below
  void updateTitle(String value, Timestamp timestamp) {
    title = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  void updateContent(String value, Timestamp timestamp) {
    content = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  void addTag(String tag, Timestamp timestamp) {
    _tags.add(tag);
    updatedAt = timestamp;
    _notifyChange();
  }

  void removeTag(String tag, Timestamp timestamp) {
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

  // serialization to json
  Map<String, dynamic> toJson() {
    return {
      'id': id.toString(),
      'title': title,
      'content': content,
      'tags': tags,
      'createdAt': createdAt.toString(),
      'updatedAt': updatedAt.toString(),
    };
  }

  // from json
  factory NoteData.fromJson(Map<String, dynamic> json) {
    return NoteData(
      GenericId.fromString(json['id']),
      json['title'],
      json['content'],
      Set<String>.from(json['tags']),
      Timestamp.fromString(json['createdAt']),
      Timestamp.fromString(json['updatedAt']),
    );
  }
}

class NoteOrderData {
  final List<GenericId> _order;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  NoteOrderData(this._order);

  List<GenericId> get items => _order;

  void add(GenericId id) {
    // add to the beginning, this list is upside down
    _order.insert(0, id);
    _notifyChange();
  }

  void moveToIndex(GenericId id, int index) {
    final current = _order.indexOf(id);

    if (current == -1) throw ArgumentError('Note not found $id');
    if (current == index) throw ArgumentError('Note already at index $index');

    _order.removeAt(current);
    _order.insert(index, id);

    _notifyChange();
  }

  void remove(GenericId id) {
    _order.remove(id);
    _notifyChange();
  }

  void _notifyChange() {
    _changeController.add(null);
  }

  void dispose() {
    _changeController.close();
  }

  // json
  Map<String, dynamic> toJson() {
    return {'order': _order.map((id) => id.toString()).toList()};
  }

  factory NoteOrderData.fromJson(Map<String, dynamic> json) {
    final order = json['order'].map((id) => GenericId.fromString(id)).toList();
    return NoteOrderData(order);
  }
}

typedef TagValue = List<GenericId>;

class TagData {
  final String name;
  final TagValue value;

  const TagData(this.name, this.value);

  factory TagData.fromJsonValue(String name, List<String> jsonValue) {
    return TagData(name, jsonValue.map(GenericId.fromString).toList());
  }
}

class TagsData {
  // association of tags to notes
  final Map<String, TagValue> _tags;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  TagsData(this._tags);
  TagsData.fromTagDataList(List<TagData> tags)
    : _tags = {for (var tag in tags) tag.name: tag.value};

  TagValue addTag(GenericId noteId, String tagName) {
    _tags[tagName] ??= [];
    final tagValue = _tags[tagName]!;

    // dont add duplicate tags!
    if (tagValue.contains(noteId)) {
      return tagValue;
    }

    tagValue.add(noteId);

    _notifyChange();
    return tagValue;
  }

  // null return value means that the tag should be deleted
  TagValue? removeTag(GenericId noteId, String tagName) {
    final list = _tags[tagName];
    if (list == null) {
      throw Exception('Tag $tagName not found');
    }

    list.remove(noteId);
    if (list.isEmpty) {
      _tags.remove(tagName);
      return null;
    }

    _notifyChange();
    return _tags[tagName]!;
  }

  // get all tags sorted alphabetically
  List<String> get values => _tags.keys.toList()..sort();

  List<GenericId> getTagNodeIds(String tag) => _tags[tag] ?? [];

  void _notifyChange() {
    _changeController.add(null);
  }

  void dispose() {
    _changeController.close();
  }
}

// this is like the full state of the application, but without flutter things.
// Managed by dispatching events
class Repo {
  final Map<GenericId, NoteData> _notes;
  final NoteOrderData _order;
  final TagsData _tags;

  const Repo(this._notes, this._order, this._tags);

  factory Repo.empty() {
    return Repo({}, NoteOrderData([]), TagsData({}));
  }

  // or init with actual event data
  // this is only used for tests
  Future<void> loadFromEvents(List<(EventId, NoteEvent)> events) async {
    // expand the names in for loop

    for (final (eventId, event) in events) {
      await processEvent(eventId, event);
    }
  }

  // Access methods that return the reactive objects
  // wrapped in the future to simulate using the database cache underneath
  Future<NoteData?> getNote(GenericId id) =>
      Future.delayed(Duration(milliseconds: 10), () => _notes[id]);

  // order could be sync, loaded at application startup
  NoteOrderData get order => _order;
  // tags could be sync, loaded at application startup
  TagsData get tags => _tags;

  void dispose() {
    _order.dispose();
    _tags.dispose();
    for (final note in _notes.values) {
      note.dispose();
    }
  }

  /// NEVER CALL FROM APPLICATION CODE
  /// only used inside the controller
  Future<void> processEvent(EventId id, NoteEvent event) async {
    // writing of event to db should happen here
    print('Processing event: [$id] $event');
    switch (event) {
      case NoteCreated event:
        _notes[event.id] = NoteData.emptyNew(event.id);
        _order.add(event.id);
        // saving of note and order to storage can happen here
        // it can actually be done outside the async event loop to speed up
        // event resolution?

        break;
      case NoteContentUpdated event:
        // the repo does not need to have everything loaded
        final note = await getNote(event.id);
        assert(note != null);
        note!.updateContent(event.content, id.timestamp);
        break;
      case NoteTitleUpdated event:
        final note = await getNote(event.id);
        assert(note != null);
        note!.updateTitle(event.title, id.timestamp);
        break;
      case NoteDeleted event:
        // TODO: this should be async too? first need to check if note exists
        // then it needs to be removed from the map
        // then it needs to be removed from disk
        final note = _notes.remove(event.id);

        if (note == null) {
          throw Exception('Note ${event.id} not found');
        }

        note.dispose();
        _order.remove(event.id);

        // remove all tags associated with the note
        for (final tag in note.tags) {
          tags.removeTag(event.id, tag);
        }

        break;
      case NoteMoved event:
        _order.moveToIndex(event.id, event.toIndex);
        break;
      case TagAssigned event:
        final note = await getNote(event.noteId);
        assert(note != null);
        note!.addTag(event.tagName, id.timestamp);
        tags.addTag(event.noteId, event.tagName);
        break;
      case TagUnassigned event:
        final note = await getNote(event.noteId);
        assert(note != null);
        note!.removeTag(event.tagName, id.timestamp);
        tags.removeTag(event.noteId, event.tagName);
        break;
    }
  }
}
