import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notes_app/notes_app.dart';

/// Keeps the last completed search while the next query is pending.
class NoteSearchController extends ChangeNotifier {
  final NotesApp application;
  String _query = '';
  Timer? _debounce;
  List<NoteState> _results = [];
  bool _hasSnapshot = false;
  bool _isReady = false;
  bool _isLoading = false;
  Exception? _readinessError;
  Exception? _searchError;
  int _generation = 0;
  bool _disposed = false;

  NoteSearchController(this.application) {
    unawaited(_waitForReadiness());
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
    _generation++;
    _debounce?.cancel();
    _debounce = null;
    if (!hasQuery) {
      _results = [];
      _hasSnapshot = false;
    }
    _searchError = null;
    _isLoading = false;
    if (hasQuery) {
      _debounce = Timer(const Duration(milliseconds: 100), () {
        _debounce = null;
        if (_readinessError != null) return;
        if (_isReady) {
          unawaited(_search());
        } else {
          _isLoading = true;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  Future<void> _waitForReadiness() async {
    try {
      await application.projectionReady;
      if (_disposed) return;
      _isReady = true;
      if (hasQuery && _debounce == null) unawaited(_search());
    } on Exception catch (error) {
      if (_disposed) return;
      _readinessError = error;
      _isLoading = false;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _search() async {
    final generation = _generation;
    _isLoading = true;
    notifyListeners();
    try {
      final results = await application.query.noteSearch(_query.trim());
      if (_disposed || generation != _generation) return;
      _results = results;
      _hasSnapshot = true;
    } on Exception catch (error) {
      if (_disposed || generation != _generation) return;
      _searchError = error;
    } finally {
      if (!_disposed && generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
