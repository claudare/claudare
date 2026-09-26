import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note.dart';

/// Tracks the latest known existence value for one note.
class NoteExistence {
  final String noteId;
  bool isActive;
  DateTime time;

  NoteExistence(this.noteId, this.isActive, this.time);
}

/// Collects note existence values by identifier.
class MakeshiftCrdt {
  final Map<String, NoteExistence> _map;

  const MakeshiftCrdt(this._map);

  int get activeCount => _map.values.where((n) => n.isActive).length;

  void applyTrashChange(String noteId, DateTime time) {
    final v = _map[noteId];
    if (v == null) {
      _map[noteId] = NoteExistence(noteId, false, time);
      return;
    }
    if (time.compareTo(v.time) > 0) {
      v.isActive = false;
      v.time = v.time;
    }
  }

  void applyRestoreChange(String noteId, DateTime time) {
    final v = _map[noteId];
    if (v == null) {
      _map[noteId] = NoteExistence(noteId, true, time);
      return;
    }
    if (time.compareTo(v.time) > 0) {
      v.isActive = true;
      v.time = v.time;
    }
  }
}

/// Counts events and active notes across all streams.
class StatisticsState implements AggregateState<Object> {
  final MakeshiftCrdt _crdt;

  int eventCount = 0;
  int get activeCount => _crdt.activeCount;

  StatisticsState() : _crdt = MakeshiftCrdt({});

  @override
  void apply(EventEnvelope<Object> envelope) {
    eventCount++;

    final event = envelope.event;
    final occuredAt = envelope.occuredAt;

    if (event is NoteEvent) {
      final noteId = event.noteId;
      switch (event) {
        case NoteCreated():
        case NoteRestored():
          _crdt.applyRestoreChange(noteId, occuredAt);
        case NoteTrashed():
          _crdt.applyTrashChange(noteId, occuredAt);
        default:
          break;
      }
    }
  }
}

Aggregate<Object, StatisticsState> statisticsAggregate() {
  return Aggregate(
    name: 'statistics',
    filter: PatternFilter.any(),
    state: StatisticsState(),
  );
}
