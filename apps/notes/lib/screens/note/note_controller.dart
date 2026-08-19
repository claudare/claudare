import 'package:flutter/material.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/command/restore_note.dart';
import 'package:notes/command/trash_note.dart';
import 'package:notes/command/update_note_content.dart';
import 'package:notes/command/update_note_title.dart';
import 'package:notes/runtime/notes_runtime.dart';

class NoteController extends ChangeNotifier {
  final NotesRuntime notesRuntime;

  String? _noteId;

  String _titleStored = ''; // title as it is stored in the database;
  String _titleLatest = '';

  String _contentStored = '';
  String _contentLatest = '';

  late DateTime _createdAt;
  late DateTime _updatedAt;
  DateTime? _trashedAt;

  bool _isLoading = false;

  NoteController(this.notesRuntime) {
    final optimisitcTime = notesRuntime.timeProvider.now();
    _createdAt = optimisitcTime;
    _updatedAt = optimisitcTime;
  }

  bool get isLoading => _isLoading;

  DateTime get createdAt => _createdAt;
  DateTime get updatedAt => _updatedAt;
  DateTime? get trashedAt => _trashedAt;

  bool get isTrashed => _trashedAt != null;

  // TODO: I dont like that this could be null
  Future<LoadResolvedText> load(String? noteId) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (noteId == null) {
        return LoadResolvedText.empty();
      }

      final noteData = await notesRuntime.resolvedNoteReadModel.getById(noteId);

      if (noteData == null) {
        throw Exception('Note not found');
      }

      assert(noteId == noteData.noteId);

      _noteId = noteData.noteId;
      _titleStored = noteData.title;
      _contentStored = noteData.content;
      _createdAt = noteData.createdAt;
      _updatedAt = noteData.updatedAt;
      _trashedAt = noteData.trashedAt;

      _titleLatest = _titleStored;
      _contentLatest = _contentStored;
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return LoadResolvedText(title: _titleStored, content: _contentStored);
  }

  /// Trashes the note.
  Future<bool> trash() async {
    if (_noteId == null) {
      throw Exception(
        'Cannot delete a note that has not been loaded or does not exist',
      );
    }

    if (_trashedAt != null) {
      notesRuntime.logger.warning('Duplicate note trashing detected');
      return false;
    }

    try {
      // always flush changes internally before trashing?
      await flushChanges();

      await notesRuntime.executeCommand(
        const TrashNote(),
        TrashNoteInput(noteId: _noteId!),
      );

      _trashedAt = notesRuntime.timeProvider.now();

      return true;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> restore() async {
    if (_noteId == null) {
      throw Exception(
        'Cannot restore a note that has not been loaded or does not exist',
      );
    }

    if (_trashedAt == null) {
      notesRuntime.logger.warning('Duplicate note restoration detected');
      return false;
    }

    try {
      await notesRuntime.executeCommand(
        const RestoreNote(),
        RestoreNoteInput(noteId: _noteId!),
      );

      _trashedAt = null;

      return true;
    } finally {
      notifyListeners();
    }
  }

  /// Returns true if changes were applied. Throws on error
  Future<bool> flushChanges() async {
    notesRuntime.logger.debug('flushing changes on note $_noteId');

    // do nothing if no note exists and nothing was changed
    if (_noteId == null && _titleLatest == '' && _contentLatest == '') {
      return false;
    }

    try {
      int changeCount = 0;

      final noteId = _noteId ?? notesRuntime.idGenerator.generateId();

      if (_noteId == null) {
        // create it
        await notesRuntime.executeCommand(
          const CreateNote(),
          CreateNoteInput(noteId: noteId),
        );

        _noteId = noteId;

        final optimisticTime = notesRuntime.timeProvider.now();
        _createdAt = optimisticTime;
        _updatedAt = optimisticTime;

        changeCount++;
      }

      // update title if it was changed
      if (_titleLatest != _titleStored) {
        await notesRuntime.executeCommand(
          const UpdateNoteTitle(),
          UpdateNoteTitleInput(noteId: noteId, fullValue: _titleLatest),
        );
        _titleStored = _titleLatest;
        changeCount++;
      }

      // update content if it was changed
      if (_contentLatest != _contentStored) {
        await notesRuntime.executeCommand(
          const UpdateNoteContent(),
          UpdateNoteContentInput(
            noteId: noteId,
            overrideContent: _contentLatest,
          ),
        );
        _contentStored = _contentLatest;
        changeCount++;
      }

      if (changeCount == 0) {
        return false;
      }

      // optimistic edit timestamp
      _updatedAt = notesRuntime.timeProvider.now();

      return true;
    } finally {
      notifyListeners();
    }
  }

  void submitTitleChange(String text) {
    _titleLatest = text;
  }

  // TODO: this will take CRDT changes instead, and keep them as a list
  // List of "emitted CrdtEvents" is used to flush
  void submitContentChange(String text) {
    _contentLatest = text;
  }

  // this is accumulated internally until a flush is called.
  // Future<void> submitContentEdit(dynamic textCqrdStuff) async {}
}

class LoadResolvedText {
  final String title;
  final String content;

  const LoadResolvedText({required this.title, required this.content});

  const LoadResolvedText.empty() : title = '', content = '';
}
