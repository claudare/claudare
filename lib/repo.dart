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

  DateTime createdAt;
  DateTime updatedAt;

  final _changeController = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changeController.stream;

  NoteData({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  // getters
  String getPreviewContent() {
    return content.length > _previewLength
        ? content.substring(0, _previewLength)
        : content;
  }

  NoteData.emptyNew(this.id, DateTime time)
    : title = '',
      content = '',
      createdAt = time,
      updatedAt = time;

  // setters here
  updateTitle(String value, DateTime timestamp) {
    title = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  updateContent(String value, DateTime timestamp) {
    content = value;
    updatedAt = timestamp;
    _notifyChange();
  }

  void _notifyChange() {
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
    _order.add(id);
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

// this is like the full state of the application, but without flutter things.
// Managed by dispatching events
class Repo {
  final Map<Id, NoteData> _notes;
  final NoteOrderData _order;

  Repo(this._notes, this._order);

  // Constructor for creating a new instance of Repo
  Repo.empty() : _notes = {}, _order = NoteOrderData([]);

  // Access methods that return the reactive objects
  NoteData? getNote(Id id) => _notes[id];
  NoteOrderData get order => _order;

  void dispose() {
    _order.dispose();
    for (final note in _notes.values) {
      note.dispose();
    }
  }

  // Method for creating a new note
  void processEvent(NoteEvent event, DateTime timestamp) {
    switch (event) {
      case NoteCreated event:
        _notes[event.id] = NoteData.emptyNew(event.id, timestamp);
        _order.add(event.id);
        break;
      case NoteBodyUpdated event:
        final note = _notes[event.id]!;
        note.updateContent(event.content, timestamp);
        break;
      case NoteDeleted event:
        final note = _notes.remove(event.id);
        note?.dispose();
        _order.remove(event.id);
        break;
      case NoteMoved event:
        _order.moveToIndex(event.id, event.toIndex);
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
}

class NoteBodyUpdated extends NoteEvent {
  final Id id;
  final String content;

  const NoteBodyUpdated(this.id, this.content);
}

class NoteDeleted extends NoteEvent {
  final Id id;

  const NoteDeleted(this.id);
}

class NoteMoved extends NoteEvent {
  final Id id;
  final int toIndex;

  const NoteMoved(this.id, this.toIndex);
}
