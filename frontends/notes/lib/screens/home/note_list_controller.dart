import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:notes_app/notes_app.dart';

/// Loads either active or trashed notes in the selected order.
class NoteListController extends ChangeNotifier {
  final NotesApp application;

  List<NoteModel> _noteData = [];
  NoteCategory _category = NoteCategory.active;
  NoteSortOrder _order = NoteSortOrder.updatedAtDescending;
  bool _isLoading = false;
  Exception? _loadError;
  bool _disposed = false;
  late final AsyncTrailingRunner _reloadRunner;
  late final _projection = application.query.liveNoteList();
  StreamSubscription<NoteListModel>? _subscription;
  Future<void>? _initialization;

  NoteListController(this.application) {
    _reloadRunner = AsyncTrailingRunner(_reloadOnce);
  }

  List<NoteModel> get noteData => _noteData;
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
      await (_initialization ??= _initialize());
      if (_disposed) return;
      await _projection.latest();
      if (_disposed) return;
      _rebuild(_projection.value!);
      _loadError = null;
    } on Exception catch (error) {
      if (!_disposed) _loadError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _initialize() async {
    final model = await _projection.latest();
    if (_disposed) return;
    _rebuild(model);
    _subscription = _projection.updates.listen(
      (model) {
        if (_disposed) return;
        _rebuild(model);
        _notify();
      },
      onError: (Object failure, StackTrace trace) {
        if (failure is! Exception) Error.throwWithStackTrace(failure, trace);
        if (_disposed) return;
        _loadError = failure;
        _notify();
      },
    );
  }

  void _rebuild(NoteListModel model) {
    _noteData = model.toSortedList(category: _category, order: _order);
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
    unawaited(_subscription?.cancel());
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _stop() async {
    try {
      await _projection.stop();
    } on Exception {
      // Loading and update failures are presented through loadError.
    }
  }
}
