import 'package:cqrs/cqrs.dart';
import 'package:notes_app/src/aggregate/note.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

enum NoteCategory { all, active, trashed }

enum NoteSortOrder {
  createdAtDescending,
  createdAtAscending,
  updatedAtDescending,
  updatedAtAscending,
}

/// Notes collected from every note stream.
class NoteListState implements AggregateState<NoteEvent> {
  final Map<String, NoteState> notes = {};

  int get activeCount => notes.values.where((note) => !note.isTrashed).length;

  /// Returns independent note states for a completed query.
  NoteListState clone() {
    final copy = NoteListState();
    for (final entry in notes.entries) {
      copy.notes[entry.key] = entry.value.clone();
    }
    return copy;
  }

  List<NoteState> toSortedList({
    NoteCategory category = NoteCategory.active,
    NoteSortOrder order = NoteSortOrder.createdAtDescending,
  }) {
    final list = notes.values.where((note) {
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

    return List.unmodifiable(list);
  }

  @override
  void apply(EventEnvelope<NoteEvent> envelope) {
    final noteId = envelope.event.noteId;
    final note = notes.putIfAbsent(noteId, () => NoteState(noteId));
    note.apply(envelope);
  }
}

Aggregate<NoteEvent, NoteListState> noteListAggregate() {
  return Aggregate(
    name: 'All notes',
    filter: allNotesFilter,
    state: NoteListState(),
  );
}
