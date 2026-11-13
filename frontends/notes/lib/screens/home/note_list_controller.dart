import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notes_app/notes_app.dart';

/// Provides live notes filtered by category and sorted in the selected order.
class NoteListController extends ChangeNotifier {
  final NotesApp application;

  NoteCategory _category = NoteCategory.active;
  NoteSortOrder _order = NoteSortOrder.updatedAtDescending;
  late final _projection = application.query.liveNoteList();

  NoteListController(this.application) {
    // Loading and replay failures are delivered through updates.
    _projection.latest().ignore();
  }

  /// Emits filtered notes when the data, category, or sort order changes.
  late final Stream<List<NoteModel>> updates = Stream.multi((controller) {
    void selectionChanged() {
      final notes = value;
      if (notes != null) controller.add(notes);
    }

    addListener(selectionChanged);
    final subscription = _projection.updates.listen(
      (model) => controller.add(_toSortedList(model)),
      onError: controller.addError,
      onDone: () {
        removeListener(selectionChanged);
        unawaited(controller.close());
      },
    );
    controller.onCancel = () {
      removeListener(selectionChanged);
      return subscription.cancel();
    };
  }, isBroadcast: true);

  List<NoteModel>? get value {
    final model = _projection.value;
    return model == null ? null : _toSortedList(model);
  }

  NoteCategory get category => _category;
  NoteSortOrder get order => _order;

  List<NoteModel> _toSortedList(NoteListModel model) =>
      model.toSortedList(category: _category, order: _order);

  void setCategory(NoteCategory category) {
    if (category == NoteCategory.all) {
      throw ArgumentError.value(category, 'category', 'Choose Notes or Trash');
    }
    if (_category == category) return;

    _category = category;
    notifyListeners();
  }

  void setOrder(NoteSortOrder order) {
    if (_order == order) return;

    _order = order;
    notifyListeners();
  }

  Future<void> deleteNotes(List<String> noteIds) async {
    for (final noteId in noteIds) {
      await application.command.trashNote(noteId);
    }
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _stop() async {
    try {
      await _projection.stop();
    } on Exception {
      // Loading and replay failures were delivered through updates.
    }
  }
}
