import 'package:cqrs/cqrs.dart';
import 'package:notes/aggregate/note.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

enum NoteCategory { all, active, trashed }

enum NoteSortOrder {
  createdAtDescending,
  createdAtAscending,
  updatedAtDescending,
  updatedAtAscending,
}

/// Notes collected from every note stream.
class NoteListState {
  final Map<String, NoteState> notes = {};

  int get activeCount => notes.values.where((note) => !note.isTrashed).length;

  List<NoteState> toSortedList({
    NoteCategory category = NoteCategory.active,
    NoteSortOrder order = NoteSortOrder.createdAtDescending,
  }) {
    final list =
        notes.values.where((note) {
          return switch (category) {
            NoteCategory.all => true,
            NoteCategory.active => !note.isTrashed,
            NoteCategory.trashed => note.isTrashed,
          };
        }).toList();

    list.sort((a, b) {
      final chronological = switch (order) {
        NoteSortOrder.createdAtAscending => a.createdAt.compareTo(b.createdAt),
        NoteSortOrder.createdAtDescending => b.createdAt.compareTo(a.createdAt),
        NoteSortOrder.updatedAtAscending => a.updatedAt.compareTo(b.updatedAt),
        NoteSortOrder.updatedAtDescending => b.updatedAt.compareTo(a.updatedAt),
      };
      return chronological != 0 ? chronological : a.noteId.compareTo(b.noteId);
    });

    return list;
  }
}

/// Replays every note stream without retaining a snapshot.
class NoteListAggregate implements Aggregate<NoteEvent, NoteListState> {
  const NoteListAggregate();

  @override
  Snapshotter<NoteListState>? get snapshotter => null;

  @override
  int get version => 1;

  @override
  StreamRoute get streamRoute => noteStreamRoute;

  @override
  NoteListState initialState() => NoteListState();

  @override
  bool canApply(EventEnvelope<NoteEvent> envelope) => true;

  @override
  void apply(NoteListState state, EventEnvelope<NoteEvent> envelope) {
    final noteId = envelope.event.noteId;
    final note = state.notes.putIfAbsent(noteId, () => NoteState(noteId));
    note.apply(envelope);
  }
}
