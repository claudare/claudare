import 'package:flutter/foundation.dart';
import 'package:notes_app_v0/command/delete_note.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/repo/note/note_read_model.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';

class NoteListController extends ChangeNotifier {
  final NotesRuntime notesRuntime;

  List<NoteData> _noteData = [];
  NoteReadModelOrder _filter = NoteReadModelOrder.createdAtDescending;
  bool _isLoading = false;

  NoteListController(this.notesRuntime);

  List<NoteData> get noteData => _noteData;
  bool get isLoading => _isLoading;

  Future<void> setFilter(NoteReadModelOrder filter) async {
    if (_filter == filter) return;

    _filter = filter;

    await reloadNotes();
  }

  Future<void> reloadNotes() async {
    if (_isLoading) {
      throw Exception('Already loading');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final data = await notesRuntime.noteReadModel.queryNonDeletedNotes(
        _filter,
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
        DeleteNoteInput(noteId: noteId),
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
