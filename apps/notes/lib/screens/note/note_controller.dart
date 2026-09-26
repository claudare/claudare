import 'package:cqrs/cqrs.dart';
import 'package:flutter/foundation.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/aggregate/note.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/event/note.dart';

class NoteController extends ChangeNotifier {
  final NoteApplication application;

  final Aggregate<NoteEvent, NoteState> _persisted;
  final bool _isNewDraft;
  String _titleLatest = '';
  late final CrdtTextEditContext content;
  bool _isLoading = false;
  bool _disposed = false;
  int _editRevision = 0;

  String get noteId => _persisted.state.noteId;
  String get _titleStored => _persisted.state.title;

  NoteController(this.application, {String? noteId})
    : _isNewDraft = noteId == null,
      _persisted = noteAggregate(noteId ?? application.generateNoteId()) {
    content = CrdtTextEditContext(
      document: _persisted.state.contentDocument,
      actorId: application.actor,
    );
    content.addListener(_onContentChanged);
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
  int get editRevision => _editRevision;
  bool get exists => _persisted.state.exists;
  DateTime? get createdAt => exists ? _persisted.state.createdAt : null;
  DateTime? get updatedAt => exists ? _persisted.state.updatedAt : null;
  DateTime? get trashedAt => _persisted.state.trashedAt;
  bool get isTrashed => _persisted.state.isTrashed;

  Future<LoadResolvedText> load() async {
    _isLoading = true;
    _notify();

    try {
      await _refreshNote();
      _titleLatest = _titleStored;
      return LoadResolvedText(title: _titleStored, content: content.text);
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
      if (_titleLatest.isEmpty && content.text.isEmpty) return false;
      await application.command.createNote(noteId);
      changed = true;
      await _refreshNote();
    }

    final title = _titleLatest;
    if (title != _titleStored) {
      await application.command.updateNoteTitle(noteId, title);
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

  void submitTitleChange(String text) {
    if (_titleLatest == text) return;
    _titleLatest = text;
    _editRevision++;
  }

  void _onContentChanged() {
    _editRevision++;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    content.removeListener(_onContentChanged);
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
