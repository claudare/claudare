import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:notes/application/note_application.dart';

class NoteListController extends ChangeNotifier {
  final NoteApplication application;

  List<NoteState> _noteData = [];
  NoteCategory _category = NoteCategory.all;
  NoteSortOrder _order = NoteSortOrder.createdAtDescending;
  bool _isLoading = false;
  Exception? _loadError;
  bool _disposed = false;
  late final AsyncTrailingRunner _reloadRunner;

  NoteListController(this.application) {
    _reloadRunner = AsyncTrailingRunner(_reloadOnce);
  }

  List<NoteState> get noteData => _noteData;
  bool get isLoading => _isLoading;
  Exception? get loadError => _loadError;

  Future<void> setCategory(NoteCategory category) async {
    if (_category == category) return;

    _category = category;

    await reloadNotes();
  }

  Future<void> setOrder(NoteSortOrder order) async {
    if (_order == order) return;

    _order = order;

    await reloadNotes();
  }

  Future<void> reloadNotes() => _reloadRunner.run();

  Future<void> _reloadOnce() async {
    _isLoading = true;
    _notify();

    try {
      final notes = await application.query.noteList();
      if (_disposed) return;
      _noteData = notes.toSortedList(category: _category, order: _order);
      _loadError = null;
    } on Exception catch (error) {
      if (!_disposed) _loadError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    try {
      for (final noteId in noteIds) {
        await application.command.trashNote(noteId);
      }
    } finally {
      await reloadNotes();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
