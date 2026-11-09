import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:notes_app/notes_app.dart';

/// Keeps the last completed search while the next query is pending.
class NoteSearchController extends ChangeNotifier {
  final NotesApp application;
  String _query = '';
  late final AsyncThrottledRunner _searchRunner;
  List<NoteState> _results = [];
  bool _hasSnapshot = false;
  bool _isReady = false;
  bool _isLoading = false;
  Future<void>? _readiness;
  Exception? _readinessError;
  Exception? _searchError;
  bool _disposed = false;

  NoteSearchController(this.application) {
    _searchRunner = AsyncThrottledRunner(_search);
  }

  String get query => _query;
  bool get hasQuery => _query.trim().isNotEmpty;
  List<NoteState> get results => _results;
  bool get hasSnapshot => _hasSnapshot;
  bool get isReady => _isReady;
  bool get isLoading => _isLoading;
  Exception? get readinessError => _readinessError;
  Exception? get searchError => _searchError;

  void setQuery(String query) {
    if (_disposed || query == _query) return;
    _query = query;
    if (!hasQuery) {
      _results = [];
      _hasSnapshot = false;
    }
    _searchError = null;
    _isLoading = hasQuery && _readinessError == null;
    if (hasQuery) {
      if (_isReady) {
        unawaited(_searchRunner.run());
      } else {
        unawaited(_readiness ??= _waitForReadiness());
      }
    }
    notifyListeners();
  }

  Future<void> _waitForReadiness() async {
    try {
      await application.startProjections().ready;
      if (_disposed) return;
      _isReady = true;
      if (hasQuery) unawaited(_searchRunner.run());
    } on Exception catch (error) {
      if (_disposed) return;
      _readinessError = error;
      _isLoading = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _search() async {
    if (_disposed || !hasQuery || !_isReady) return;
    final query = _query;
    _isLoading = true;
    notifyListeners();
    try {
      final results = await application.query.noteSearch(query.trim());
      if (_disposed || query != _query) return;
      _results = results;
      _hasSnapshot = true;
    } on Exception catch (error) {
      if (_disposed || query != _query) return;
      _searchError = error;
    } finally {
      if (!_disposed && query == _query) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
