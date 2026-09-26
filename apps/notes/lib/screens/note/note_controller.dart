import 'package:flutter/foundation.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/event/note.dart';

class NoteController extends ChangeNotifier {
  final NoteApplication application;

  String? _noteId;
  NoteState? _persisted;
  int _nextVersion = 0;
  String _titleStored = '';
  String _titleLatest = '';
  final CrdtTextEditContext content;
  DateTime? _createdAt;
  DateTime? _updatedAt;
  DateTime? _trashedAt;
  bool _isLoading = false;
  bool _disposed = false;
  int _editRevision = 0;

  NoteController(this.application)
    : content = CrdtTextEditContext(
        document: CrdtText(),
        actorId: application.actor,
      ) {
    content.addListener(_onContentChanged);
  }

  /// Delivers new persisted events to the current editing draft.
  Future<void> refresh() => _refreshNote();

  Future<void> simulateExternalEdit() async {
    final noteId = _noteId;
    if (noteId == null || isTrashed) return;
    await application.command.testSimulateExternalNoteContentRandomInsert(
      noteId,
      '\nWhy hello there\n',
      actorId: '${application.actor}-simulation',
    );
  }

  bool get isLoading => _isLoading;
  int get editRevision => _editRevision;
  bool get exists => _persisted?.exists ?? false;
  DateTime? get createdAt => _createdAt;
  DateTime? get updatedAt => _updatedAt;
  DateTime? get trashedAt => _trashedAt;
  bool get isTrashed => _trashedAt != null;

  Future<LoadResolvedText> load(String? noteId) async {
    _isLoading = true;
    _notify();

    try {
      if (noteId == null) return const LoadResolvedText.empty();

      _noteId = noteId;
      await _refreshNote();
      _titleLatest = _titleStored;
      return LoadResolvedText(title: _titleStored, content: content.text);
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<bool> trash() async {
    final noteId = _noteId;
    if (noteId == null) {
      throw Exception('Cannot trash a note that has not been saved');
    }
    if (_trashedAt != null) return false;

    await flushChanges();
    await application.command.trashNote(noteId);
    await _refreshNote();
    return true;
  }

  Future<bool> restore() async {
    final noteId = _noteId;
    if (noteId == null) {
      throw Exception('Cannot restore a note that has not been loaded');
    }
    if (_trashedAt == null) return false;

    await application.command.restoreNote(noteId);
    await _refreshNote();
    return true;
  }

  /// Returns true when a command wrote a change.
  Future<bool> flushChanges() async {
    if (_noteId == null && _titleLatest.isEmpty && content.text.isEmpty) {
      return false;
    }

    var changed = false;
    if (_noteId == null) {
      _noteId = await application.command.createNote();
      changed = true;
      await _refreshNote();
    }

    final noteId = _noteId!;
    final title = _titleLatest;
    if (title != _titleStored) {
      await application.command.updateNoteTitle(noteId, title);
      changed = true;
      await _refreshNote();
    }

    final change = content.prepareChange();
    if (change != null) {
      await application.command.updateNoteContent(noteId, change);
      content.acknowledgeChange(change);
      changed = true;
      await _refreshNote();
    }

    if (_createdAt == null) await _refreshNote();
    return changed;
  }

  Future<void> _refreshNote() async {
    final noteId = _noteId!;
    final note = _persisted ??= NoteState(noteId);
    try {
      await for (final delivery in application.query.noteEvents(
        noteId,
        fromVersion: _nextVersion,
      )) {
        if (_disposed) return;
        final event = delivery.envelope.event;
        if (event is NoteContentUpdated) content.applyChange(event.change);
        note.apply(delivery.envelope);
        _nextVersion = delivery.version + 1;
      }
      if (!note.exists) throw Exception('Note not found');
    } finally {
      if (note.exists) _applyNote(note);
      _notify();
    }
  }

  void _applyNote(NoteState note) {
    _titleStored = note.title;
    _createdAt = note.createdAt;
    _updatedAt = note.updatedAt;
    _trashedAt = note.trashedAt;
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
