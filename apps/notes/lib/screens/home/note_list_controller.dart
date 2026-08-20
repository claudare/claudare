import 'dart:async';

import 'package:common/common.dart';
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
  late final AsyncTrailingRunner _reloadRunner;

  NoteListController(this.application) {
    _reloadRunner = AsyncTrailingRunner(_reloadOnce);
    application.resolvedNoteReadModelNotifier.addListener(
      _onResolvedNoteReadModelChanged,
    );
  }

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

  Future<void> reloadNotes() => _reloadRunner.run();

  Future<void> _reloadOnce() async {
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

  void _onResolvedNoteReadModelChanged() {
    unawaited(reloadNotes());
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    final promises = noteIds.map(
      (noteId) => application.commandExecute(
        const TrashNote(),
        TrashNoteInput(noteId: noteId),
      ),
    );

    await Future.wait(promises);
  }

  @override
  void dispose() {
    application.resolvedNoteReadModelNotifier.removeListener(
      _onResolvedNoteReadModelChanged,
    );
    super.dispose();
  }
}
