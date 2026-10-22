import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:notes_app/notes_app.dart';

/// Loads either active or trashed notes in the selected order.
class NoteListController extends ChangeNotifier {
  final NotesApp application;

  List<NoteState> _noteData = [];
  NoteCategory _category = NoteCategory.active;
  NoteSortOrder _order = NoteSortOrder.updatedAtDescending;
  bool _isLoading = false;
  Exception? _loadError;
  bool _disposed = false;
  late final AsyncTrailingRunner _reloadRunner;
  late final StreamSubscription<void> _noteListChanges;

  NoteListController(this.application) {
    _reloadRunner = AsyncTrailingRunner(_reloadOnce);
    _noteListChanges = application.query.noteListChanges().listen((_) {
      unawaited(reloadNotes());
    });
  }

  List<NoteState> get noteData => _noteData;
  NoteCategory get category => _category;
  NoteSortOrder get order => _order;
  bool get isLoading => _isLoading;
  Exception? get loadError => _loadError;

  Future<void> setCategory(NoteCategory category) async {
    if (category == NoteCategory.all) {
      throw ArgumentError.value(category, 'category', 'Choose Notes or Trash');
    }
    if (_category == category) return;

    _category = category;
    _noteData = [];

    await reloadNotes();
  }

  Future<void> setOrder(NoteSortOrder order) async {
    if (_order == order) return;

    _order = order;
    _noteData = [];

    await reloadNotes();
  }

  Future<void> reloadNotes() => _reloadRunner.run();

  Future<void> _reloadOnce() async {
    _isLoading = true;
    _notify();

    try {
      final category = _category;
      final order = _order;
      final notes = await application.query.noteList(
        category: category,
        order: order,
      );
      if (_disposed) return;
      if (category != _category || order != _order) return;
      _noteData = notes;
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
    unawaited(_noteListChanges.cancel());
    super.dispose();
  }
}
