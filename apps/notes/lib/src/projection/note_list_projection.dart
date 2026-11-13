import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:notes_app/src/projection/note_projection.dart';
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
class NoteListProjection implements Projection<NoteListModel, NoteEvent> {
  @override
  String get name => 'note-list';

  @override
  LogFilter get filter => allNotesFilter;

  @override
  FutureOr<ProjectionLoad<NoteListModel>> load() =>
      ProjectionLoad.initial(NoteListModel._());

  @override
  void apply(model, envelope) {
    final noteId = noteIdFromStream(envelope.streamPath);
    final note = model._notes.putIfAbsent(
      noteId,
      () => NoteProjection(noteId).load().model,
    );
    NoteProjection(noteId).apply(note, envelope);
  }

  @override
  void onStreamDeleted(model, deletion) {
    final noteId = noteIdFromStream(deletion.streamPath);
    final note = model._notes.remove(noteId);
    if (note != null) NoteProjection(noteId).onStreamDeleted(note, deletion);
  }
}

/// Current notes with category and chronological ordering queries.
class NoteListModel {
  final Map<String, NoteModel> _notes = {};

  int get activeCount => _notes.values.where((note) => !note.isTrashed).length;

  NoteListModel._();

  List<NoteModel> toSortedList({
    NoteCategory category = NoteCategory.active,
    NoteSortOrder order = NoteSortOrder.createdAtDescending,
  }) {
    final list = _notes.values.where((note) {
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
}
