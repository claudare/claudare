import 'package:crdt/src/string/crdt_string.dart';
import 'package:crdt/src/string/crdt_string_change.dart';

/// A local string draft whose prepared values are acknowledged by replay.
///
/// Persist [prepareChange] results with [actorId] and a persistence timestamp,
/// then apply those changes to [document]. Each writer needs a distinct actor.
final class CrdtStringEditContext {
  final CrdtString document;
  final String actorId;
  final List<void Function()> _listeners = [];
  String _value;
  String? _prepared;
  int _revision = 0;
  int _preparedRevision = 0;
  bool _dirty = false;
  bool _notificationPending = false;

  CrdtStringEditContext({required this.document, required this.actorId})
    : _value = document.value {
    if (actorId.isEmpty) throw ArgumentError.value(actorId, 'actorId');
    document.addListener(_reconcile);
  }

  String get value => _value;

  set value(String value) {
    if (_value == value) return;
    _value = value;
    _revision++;
    _dirty = _prepared != null || value != document.value;
    _notify();
  }

  bool get hasPendingChanges => _prepared != null || _dirty;

  /// Captures a value for persistence, retaining it until its replay arrives.
  /// An empty string is a change; null means there is nothing to save.
  String? prepareChange() {
    if (_prepared != null) return _prepared;
    if (!_dirty) return null;
    _preparedRevision = _revision;
    return _prepared = _value;
  }

  void _reconcile(CrdtStringChange change) {
    if (_prepared != null &&
        change.actor == actorId &&
        change.value == _prepared) {
      _prepared = null;
      _dirty = _revision != _preparedRevision && _value != document.value;
    }
    final previous = _value;
    if (!_dirty) _value = document.value;
    if (_value != previous || _notificationPending) _notify();
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    _notificationPending = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _notificationPending = false;
  }

  /// Detaches this draft from its persisted source.
  void dispose() => document.removeListener(_reconcile);
}
