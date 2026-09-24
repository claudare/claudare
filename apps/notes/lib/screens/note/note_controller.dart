import 'package:flutter/foundation.dart';
import 'package:notes/application/note_application.dart';

class NoteController extends ChangeNotifier {
  final NoteApplication application;

  String? _noteId;
  String _titleStored = '';
  String _titleLatest = '';
  String _contentStored = '';
  String _contentLatest = '';
  DateTime? _createdAt;
  DateTime? _updatedAt;
  DateTime? _trashedAt;
  bool _isLoading = false;
  bool _disposed = false;
  int _editRevision = 0;

  NoteController(this.application);

  bool get isLoading => _isLoading;
  int get editRevision => _editRevision;
  bool get exists => _noteId != null;
  DateTime? get createdAt => _createdAt;
  DateTime? get updatedAt => _updatedAt;
  DateTime? get trashedAt => _trashedAt;
  bool get isTrashed => _trashedAt != null;

  Future<LoadResolvedText> load(String? noteId) async {
    _isLoading = true;
    _notify();

    try {
      if (noteId == null) return const LoadResolvedText.empty();

      final note = await application.query.note(noteId);
      if (note == null) throw Exception('Note not found');

      _noteId = note.noteId;
      _applyNote(note);
      _titleLatest = _titleStored;
      _contentLatest = _contentStored;
      return LoadResolvedText(title: _titleStored, content: _contentStored);
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
    if (_noteId == null && _titleLatest.isEmpty && _contentLatest.isEmpty) {
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

    final content = _contentLatest;
    if (content != _contentStored) {
      await application.command.updateNoteContent(noteId, content);
      changed = true;
      await _refreshNote();
    }

    if (_createdAt == null) await _refreshNote();
    return changed;
  }

  Future<void> _refreshNote() async {
    final noteId = _noteId!;
    final note = await application.query.note(noteId);
    if (note == null) {
      throw StateError('Saved note $noteId was not found');
    }
    _applyNote(note);
    _notify();
  }

  void _applyNote(NoteState note) {
    _titleStored = note.title;
    _contentStored = note.content;
    _createdAt = note.createdAt;
    _updatedAt = note.updatedAt;
    _trashedAt = note.trashedAt;
  }

  void submitTitleChange(String text) {
    if (_titleLatest == text) return;
    _titleLatest = text;
    _editRevision++;
  }

  void submitContentChange(String text) {
    if (_contentLatest == text) return;
    _contentLatest = text;
    _editRevision++;
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

class LoadResolvedText {
  final String title;
  final String content;

  const LoadResolvedText({required this.title, required this.content});

  const LoadResolvedText.empty() : title = '', content = '';
}
