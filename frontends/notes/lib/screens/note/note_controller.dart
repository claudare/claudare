import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:flutter/foundation.dart';
import 'package:crdt/crdt_text.dart';
import 'package:crdt/crdt_string.dart';
import 'package:notes_app/notes_app.dart';

class NoteController extends ChangeNotifier {
  final NotesApp application;

  NoteModel? _model;
  NoteModel get _persisted => _model!;
  late final LiveProjection<NoteModel, Object> _live;
  StreamSubscription<NoteModel>? _subscription;
  Future<void>? _initialization;
  Exception? error;
  final String noteId;
  final bool _isNewDraft;
  late final CrdtStringEditContext title;
  late final CrdtTextEditContext content;
  bool _isLoading = false;
  bool _disposed = false;

  NoteController(this.application, {String? noteId})
    : _isNewDraft = noteId == null,
      noteId = noteId ?? application.generateNoteId() {
    _live = application.query.liveNote(this.noteId);
  }

  Future<void> _initialize() async {
    final model = await _live.latest();
    if (_disposed) return;
    _model = model;
    title = CrdtStringEditContext(
      document: model.titleDocument,
      actorId: application.actor,
    );
    content = CrdtTextEditContext(
      document: model.contentDocument,
      actorId: application.actor,
    );
    _subscription = _live.updates.listen(
      (model) {
        if (_disposed) return;
        if (model.isDeleted || (!model.exists && !_isNewDraft)) {
          error = Exception('Note not found');
        }
        _notify();
      },
      onError: (Object failure, StackTrace trace) {
        if (failure is! Exception) Error.throwWithStackTrace(failure, trace);
        if (_disposed) return;
        error = failure;
        _notify();
      },
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
      _model != null && (title.hasPendingChanges || content.hasPendingChanges);
  bool get exists => _model?.exists ?? false;
  DateTime? get createdAt => exists ? _persisted.createdAt : null;
  DateTime? get updatedAt => exists ? _persisted.updatedAt : null;
  DateTime? get trashedAt => _model?.trashedAt;
  bool get isTrashed => _model?.isTrashed ?? false;

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
      await (_initialization ??= _initialize());
      if (_disposed) throw const ProjectionStoppedException();
      if (error != null) throw error!;
      await _live.latest();
      if (_persisted.isDeleted || (!exists && !_isNewDraft)) {
        throw Exception('Note not found');
      }
    } finally {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _close() async {
    await _subscription?.cancel();
    try {
      await _live.stop();
    } on Exception {
      // Projection failures were delivered through loading or updates.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_model != null) {
      title.dispose();
      content.dispose();
    }
    unawaited(_close());
    super.dispose();
  }
}

class LoadResolvedText {
  final String title;
  final String content;

  const LoadResolvedText({required this.title, required this.content});

  const LoadResolvedText.empty() : title = '', content = '';
}
