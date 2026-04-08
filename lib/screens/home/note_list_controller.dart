import 'package:flutter/foundation.dart';
import 'package:notes_app_v0/command/trash_note.dart';
import 'package:notes_app_v0/model/resolved_note.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';

class NoteListController extends ChangeNotifier {
  final NotesRuntime notesRuntime;

  List<ResolvedNote> _noteData = [];
  ResolvedNoteQueryCategory _category = ResolvedNoteQueryCategory.all;
  ResolvedNoteQueryOrder _order = ResolvedNoteQueryOrder.createdAtDescending;
  bool _isLoading = false;

  NoteListController(this.notesRuntime);

  List<ResolvedNote> get noteData => _noteData;
  bool get isLoading => _isLoading;

  Future<void> setCategory(ResolvedNoteQueryCategory category) async {
    if (_category == category) return;

    _category = category;

    await reloadNotes();
  }

  Future<void> setFilter(ResolvedNoteQueryOrder filter) async {
    if (_order == filter) return;

    _order = filter;

    await reloadNotes();
  }

  Future<void> reloadNotes() async {
    if (_isLoading) {
      throw Exception('Already loading');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final data = await notesRuntime.resolvedNoteReadModel.query(
        _category,
        _order,
      );
      _noteData = data;
    } catch (e) {
      print('ERROR LOADING NOTES: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    final promises = noteIds.map(
      (noteId) => notesRuntime.commands.deleteNote.runResult(
        TrashNoteInput(noteId: noteId),
      ),
    );

    final results = await Future.wait(promises);

    for (final result in results) {
      if (!result.success) {
        print('Failed to delete note: $result');
      }
    }

    await reloadNotes();
  }
}
