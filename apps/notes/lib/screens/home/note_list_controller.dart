import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:notes/application/note_application.dart';

/// Keeps the visible note list current while the controller is alive.
class NoteListController extends ChangeNotifier {
  final NoteApplication application;

  List<NoteState> _noteData = [];
  StreamSubscription<void>? _changes;
  Future<void>? _initialization;
  late final AsyncTrailingRunner _reloadRunner = AsyncTrailingRunner(
    _reloadOnce,
  );
  NoteCategory _category = NoteCategory.all;
  NoteSortOrder _order = NoteSortOrder.createdAtDescending;
  bool _isLoading = false;
  Exception? _loadError;
  bool _disposed = false;

  NoteListController(this.application);

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

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (_disposed) return;

    _changes = application.query.noteListChanges().listen(
      (_) => unawaited(reloadNotes()),
    );

    await reloadNotes();
  }

  Future<void> reloadNotes() => _reloadRunner.run();

  Future<void> _reloadOnce() async {
    if (_disposed) return;
    _isLoading = true;
    _notify();

    try {
      final notes = await application.query.noteList(
        category: _category,
        order: _order,
      );
      if (_disposed) return;
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
    for (final noteId in noteIds) {
      await application.command.trashNote(noteId);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
