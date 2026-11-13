import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

/// Tracks the latest known existence value for one note.
class _NoteExistence {
  final String noteId;
  bool isActive;
  DateTime time;

  _NoteExistence(this.noteId, this.isActive, this.time);
}

/// Collects note existence values by identifier.
class _MakeshiftCrdt {
  final Map<String, _NoteExistence> _map;

  const _MakeshiftCrdt(this._map);

  int get activeCount => _map.values.where((n) => n.isActive).length;

  void applyTrashChange(String noteId, DateTime time) {
    final v = _map[noteId];
    if (v == null) {
      _map[noteId] = _NoteExistence(noteId, false, time);
      return;
    }
    if (time.compareTo(v.time) >= 0) {
      v.isActive = false;
      v.time = time;
    }
  }

  void applyRestoreChange(String noteId, DateTime time) {
    final v = _map[noteId];
    if (v == null) {
      _map[noteId] = _NoteExistence(noteId, true, time);
      return;
    }
    if (time.compareTo(v.time) >= 0) {
      v.isActive = true;
      v.time = time;
    }
  }
}

/// Counts active notes across all streams.
class StatisticsProjection implements Projection<StatisticsModel, Object> {
  @override
  String get name => 'statistics';

  @override
  LogFilter get filter => LogFilter.all();

  @override
  FutureOr<ProjectionLoad<StatisticsModel>> load() =>
      ProjectionLoad.initial(StatisticsModel._());

  @override
  void apply(model, envelope) {
    final event = envelope.event;
    final occuredAt = envelope.occuredAt;

    if (event is NoteEvent) {
      final noteId = noteIdFromStream(envelope.streamPath);
      switch (event) {
        case NoteCreated():
        case NoteRestored():
          model._crdt.applyRestoreChange(noteId, occuredAt);
        case NoteTrashed():
          model._crdt.applyTrashChange(noteId, occuredAt);
        default:
          break;
      }
    }
  }

  @override
  void onStreamDeleted(model, deletion) {
    if (!allNotesFilter.doesMatchPath(deletion.streamPath)) return;
    final noteId = noteIdFromStream(deletion.streamPath);
    model._crdt._map.remove(noteId);
  }
}

/// Current note counts maintained by [StatisticsProjection].
class StatisticsModel {
  final _MakeshiftCrdt _crdt = _MakeshiftCrdt({});

  int get activeCount => _crdt.activeCount;

  StatisticsModel._();
}
