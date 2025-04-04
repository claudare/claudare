import 'dart:async';

import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:notes_app_v0/app_store.dart';
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
    updatedAt = timestamp.max(updatedAt);
    _notifyChange();
  }

  void updateContent(String value, Timestamp timestamp) {
    content = value;
    updatedAt = timestamp.max(updatedAt);
    _notifyChange();
  }

  void addTag(String tag, Timestamp timestamp) {
    _tags.add(tag);
    updatedAt = timestamp.max(updatedAt);
    _notifyChange();
  }

  void removeTag(String tag, Timestamp timestamp) {
    _tags.remove(tag);
    updatedAt = timestamp.max(updatedAt);
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

  void clear() {
    _order.clear();
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
    final List<GenericId> order =
        (json['order'] as List<dynamic>)
            .map((id) => GenericId.fromString(id.toString()))
            .toList();

    return NoteOrderData(order);
  }
}

typedef TagValue = List<GenericId>;

class TagData {
  final String name;
  final TagValue value;

  const TagData(this.name, this.value);

  List<String> toJsonValue() {
    return value.map((id) => id.toString()).toList();
  }

  factory TagData.fromJsonValue(String name, List<dynamic> jsonValue) {
    return TagData(
      name,
      jsonValue.map((id) => GenericId.fromString(id)).toList(),
    );
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

  TagData addTag(GenericId noteId, String tagName) {
    _tags[tagName] ??= [];
    final tagValue = _tags[tagName]!;

    // dont add duplicate tags!
    if (tagValue.contains(noteId)) {
      return TagData(tagName, tagValue);
    }

    _tags[tagName]!.add(noteId);

    _notifyChange();
    return TagData(tagName, _tags[tagName]!);
  }

  // null return value means that the tag should be deleted
  TagData? removeTag(GenericId noteId, String tagName) {
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
    return TagData(tagName, _tags[tagName]!);
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
  final AppStore _appStore;
  final Map<GenericId, NoteData> _notes;

  // these are loaded right away
  late NoteOrderData _order;
  NoteOrderData _searchOrder;
  late TagsData _tags;

  Repo(this._appStore, this._notes, this._order, this._searchOrder, this._tags);

  factory Repo.empty(AppStore appStore) {
    return Repo(
      appStore,
      {},
      NoteOrderData([]),
      NoteOrderData([]),
      TagsData({}),
    );
  }

  // or init with actual event data
  // this is only used for tests
  Future<void> loadFromEvents(List<(EventId, NoteEvent)> events) async {
    // expand the names in for loop

    for (final (eventId, event) in events) {
      await processEvent(eventId, event);
    }
  }

  Future<void> loadFromAppStore() async {
    _order = await _appStore.noteOrderGet();
    _tags = await _appStore.tagsGet();
  }

  // Access methods that return the reactive objects
  // TODO: the map needs to be cleaned up eventually...
  Future<NoteData?> getNote(GenericId id) async {
    final mapValue = _notes[id];

    if (mapValue != null) {
      return mapValue;
    }

    final maybeValue = await _appStore.noteGet(id);

    if (maybeValue == null) {
      return null;
    }

    _notes[id] = maybeValue;
    return maybeValue;
  }

  // order could be sync, loaded at application startup
  NoteOrderData get order => _order;
  NoteOrderData get searchOrder => _searchOrder;
  // tags could be sync, loaded at application startup
  TagsData get tags => _tags;

  Future<void> searchNote(String query) async {
    if (query.isEmpty) {
      _searchOrder.items.clear();
      _searchOrder._notifyChange();
      return;
    }

    final ids = await _appStore.noteSearchQuery(query);

    _searchOrder.items.clear();
    _searchOrder.items.addAll(ids);
    // notify of change once
    _searchOrder._notifyChange();
  }

  // TODO: actually cleanup the memory
  void deinit() {
    _order.dispose();
    _searchOrder.dispose();
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

        // ugly autoincrement
        await _appStore.noteSave(_notes[event.id]!);
        await _appStore.noteOrderSave(_order);

        await _appStore.noteSearchInit(event.id);

        break;
      case NoteContentUpdated event:
        // the repo does not need to have everything loaded
        final note = await getNote(event.id);
        assert(note != null);
        note!.updateContent(event.content, id.timestamp);

        await _appStore.noteSave(_notes[event.id]!);
        await _appStore.noteSearchUpdate(event.id, content: note.content);

        break;
      case NoteTitleUpdated event:
        final note = await getNote(event.id);
        assert(note != null);
        note!.updateTitle(event.title, id.timestamp);

        await _appStore.noteSave(_notes[event.id]!);
        await _appStore.noteSearchUpdate(event.id, title: note.title);

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

        await _appStore.noteDelete(event.id);
        await _appStore.noteOrderSave(_order);

        await _appStore.noteSearchDelete(event.id);

        // remove all tags associated with the note
        for (final tagName in note.tags) {
          final tagState = tags.removeTag(event.id, tagName);

          if (tagState == null) {
            await _appStore.tagDelete(tagName);
          } else {
            await _appStore.tagSave(tagState);
          }
        }

        break;
      case NoteMoved event:
        _order.moveToIndex(event.id, event.toIndex);
        await _appStore.noteOrderSave(_order);

        break;
      case TagAssigned event:
        final note = await getNote(event.noteId);
        assert(note != null);
        note!.addTag(event.tagName, id.timestamp);
        final tagData = tags.addTag(event.noteId, event.tagName);

        await _appStore.noteSave(note);
        await _appStore.tagSave(tagData);

        print('saving tags: ${note.tags.join(' ')}');
        await _appStore.noteSearchUpdate(
          event.noteId,
          tags: note.tags.join(' '),
        );

        break;
      case TagUnassigned event:
        final note = await getNote(event.noteId);
        assert(note != null);
        note!.removeTag(event.tagName, id.timestamp);
        final tagData = tags.removeTag(event.noteId, event.tagName);

        await _appStore.noteSave(note);
        if (tagData == null) {
          await _appStore.tagDelete(event.tagName);
        } else {
          await _appStore.tagSave(tagData);
        }

        await _appStore.noteSearchUpdate(
          event.noteId,
          tags: note.tags.join(' '),
        );

        break;
    }
  }
}
