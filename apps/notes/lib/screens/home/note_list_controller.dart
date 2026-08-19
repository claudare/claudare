import 'package:flutter/foundation.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/read_model/note/resolved_note.dart';
import 'package:notes/read_model/note/resolved_note_read_model.dart';

class NoteListController extends ChangeNotifier {
  final NoteApplication application;

  List<ResolvedNote> _noteData = [];
  ResolvedNoteQueryCategory _category = ResolvedNoteQueryCategory.all;
  ResolvedNoteQueryOrder _order = ResolvedNoteQueryOrder.createdAtDescending;
  String _search = '';
  bool _isLoading = false;

  NoteListController(this.application);

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

  Future<void> setSearch(String search) async {
    if (_search == search) return;

    _search = search;

    await reloadNotes();
  }

  Future<void> reloadNotes() async {
    if (_isLoading) {
      throw Exception('Already loading');
    }

    _isLoading = true;
    notifyListeners();

    try {
      // final data = await application.resolvedNoteReadModel.query(
      //   _category,
      //   _order,
      // );
      final data = await application.compositeNoteSearch.queryComposite(
        _search,
        _category,
        _order,
      );
      _noteData = data;
    } on Exception catch (error, stackTrace) {
      application.logger.error(
        'Failed to load notes: $error',
        error,
        stackTrace,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    final promises = noteIds.map(
      (noteId) => application.commandExecute(
        const TrashNote(),
        TrashNoteInput(noteId: noteId),
      ),
    );

    await Future.wait(promises);

    await reloadNotes();
  }
}
