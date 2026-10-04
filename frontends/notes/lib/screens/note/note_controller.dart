import 'package:flutter/foundation.dart';
import 'package:crdt/crdt_text.dart';
import 'package:crdt/crdt_string.dart';
import 'package:notes_app/notes_app.dart';

class NoteController extends ChangeNotifier {
  final NotesApp application;

  final NoteState _persisted;
  final bool _isNewDraft;
  late final CrdtStringEditContext title;
  late final CrdtTextEditContext content;
  bool _isLoading = false;
  bool _disposed = false;

  String get noteId => _persisted.noteId;

  NoteController(this.application, {String? noteId})
    : _isNewDraft = noteId == null,
      _persisted = application.query.trackNote(
        noteId ?? application.generateNoteId(),
      ) {
    title = CrdtStringEditContext(
      document: _persisted.titleDocument,
      actorId: application.actor,
    );
    content = CrdtTextEditContext(
      document: _persisted.contentDocument,
      actorId: application.actor,
    );
  }

  /// Delivers new persisted events to the current editing draft.
  Future<void> refresh() => _refreshNote();

  Future<void> simulateExternalEdit() async {
    if (!exists || isTrashed) return;
    await application.command.testSimulateExternalNoteContentRandomInsert(
      noteId,
      '[Why hello there]',
      actorId: '${application.actor}-simulation',
    );
  }

  bool get isLoading => _isLoading;
  bool get hasPendingChanges =>
      title.hasPendingChanges || content.hasPendingChanges;
  bool get exists => _persisted.exists;
  DateTime? get createdAt => exists ? _persisted.createdAt : null;
  DateTime? get updatedAt => exists ? _persisted.updatedAt : null;
  DateTime? get trashedAt => _persisted.trashedAt;
  bool get isTrashed => _persisted.isTrashed;

  Future<LoadResolvedText> load() async {
    _isLoading = true;
    _notify();

    try {
      await _refreshNote();
      return LoadResolvedText(title: title.value, content: content.text);
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<bool> trash() async {
    if (!exists) {
      throw Exception('Cannot trash a note that has not been saved');
    }
    if (isTrashed) return false;

    await flushChanges();
    await application.command.trashNote(noteId);
    await _refreshNote();
    return true;
  }

  Future<bool> restore() async {
    if (!exists) {
      throw Exception('Cannot restore a note that has not been loaded');
    }
    if (!isTrashed) return false;

    await application.command.restoreNote(noteId);
    await _refreshNote();
    return true;
  }

  /// Returns true when a command wrote a change.
  Future<bool> flushChanges() async {
    await _refreshNote();

    var changed = false;
    if (!exists) {
      if (title.value.isEmpty && content.text.isEmpty) return false;
      await application.command.createNote(noteId);
      changed = true;
      await _refreshNote();
    }

    final titleChange = title.prepareChange();
    if (titleChange != null) {
      await application.command.updateNoteTitle(noteId, titleChange);
      changed = true;
      await _refreshNote();
    }

    final change = content.prepareChange();
    if (change != null) {
      await application.command.updateNoteContent(noteId, change);
      changed = true;
      await _refreshNote();
    }

    return changed;
  }

  Future<void> _refreshNote() async {
    try {
      await application.query.catchupNote(_persisted);
      if (!exists && !_isNewDraft) throw Exception('Note not found');
    } finally {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    _disposed = true;
    super.dispose();
  }
}

class LoadResolvedText {
  final String title;
  final String content;

  const LoadResolvedText({required this.title, required this.content});

  const LoadResolvedText.empty() : title = '', content = '';
}
