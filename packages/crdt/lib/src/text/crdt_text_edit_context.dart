part of 'crdt_text.dart';

/// An editing view of [document] plus pending local edits.
///
/// Applied document changes update the draft and acknowledge prepared edits.
/// Each independent writer must use a distinct [actorId]. Pending edits exist
/// only in memory. Call [dispose] when the context is no longer needed.
final class CrdtTextEditContext {
  final String actorId;
  final CrdtText document;
  final CrdtText _draft;
  final List<CrdtTextOperation> _pending = [];
  CrdtTextChange? _prepared;

  CrdtTextEditContext({required this.document, required this.actorId})
    : _draft = document.fork() {
    _requireActor(actorId);
    document.addListener(_reconcile);
  }

  String get text => _draft.text;

  /// The UTF-16 length, matching Dart strings and editor offsets.
  int get length => _draft.length;

  bool get hasPendingChanges => _pending.isNotEmpty;

  void insert(int offset, String text) => replace(offset, offset, text);

  void delete(int start, int end) => replace(start, end, '');

  /// Replaces [start] through the exclusive [end] as one local mutation.
  ///
  /// Offsets must fall on Unicode scalar boundaries.
  void replace(int start, int end, String text) {
    final atoms = _draft._visibleAtoms();
    final content = atoms.map((atom) => atom.character).join();
    RangeError.checkValidRange(start, end, content.length);
    final first = _scalarIndex(atoms, start);
    final last = _scalarIndex(atoms, end);
    _scalars(text);
    if (content.substring(start, end) == text) return;
    _replaceIds(
      atoms.sublist(first, last).map((atom) => atom.id).toList(),
      first == 0 ? null : atoms[first - 1].id,
      text,
    );
  }

  void _reconcile() {
    final prepared = _prepared;
    final acknowledged = prepared != null && _isApplied(prepared);
    final remaining =
        _pending.length - (acknowledged ? prepared.operations.length : 0);
    final operations = document._operations.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    if (remaining > 0 &&
        operations.any(
          (operation) =>
              operation.id.actorId == actorId &&
              !_draft._operations.containsKey(operation.id),
        )) {
      throw const CrdtTextException(
        'Another writer cannot extend this actor while local edits are pending.',
      );
    }
    final changed = _draft._integrate(operations);
    if (acknowledged) {
      _pending.removeRange(0, prepared.operations.length);
      _prepared = null;
    }
    if (changed || _draft._notificationPending) _draft._notify();
  }

  /// Captures unsaved edits; repeated calls return the same batch until saved.
  CrdtTextChange? prepareChange() {
    if (_prepared != null) return _prepared;
    if (_pending.isEmpty) return null;
    final change = CrdtTextChange(_pending);
    if (_isApplied(change)) {
      _pending.clear();
      return null;
    }
    return _prepared = change;
  }

  bool _isApplied(CrdtTextChange change) => change.operations.every(
    (operation) => document._operations[operation.id] == operation,
  );

  /// Detaches the context from its source document.
  void dispose() => document.removeListener(_reconcile);

  /// Observes accepted draft edits after the full mutation commits.
  void addListener(void Function() listener) => _draft.addListener(listener);

  void removeListener(void Function() listener) =>
      _draft.removeListener(listener);

  List<CrdtTextInsert> _replaceIds(
    List<CrdtTextId> targets,
    CrdtTextId? after,
    String replacement,
  ) {
    final characters = _scalars(replacement);
    final count = targets.length + characters.length;
    if (count == 0) return [];
    var counter = _greatestCounter(_draft._version);
    if (count > _maxCounter - counter) {
      throw StateError('The document has exhausted its exact JSON counters.');
    }
    final version = Map<String, int>.of(_draft._version);
    final operations = <CrdtTextOperation>[];
    final inserted = <CrdtTextInsert>[];
    for (final target in targets) {
      final id = CrdtTextId(actorId: actorId, counter: ++counter);
      operations.add(
        CrdtTextDelete(id: id, dependencies: version, target: target),
      );
      version[actorId] = counter;
    }
    for (final character in characters) {
      final id = CrdtTextId(actorId: actorId, counter: ++counter);
      final operation = CrdtTextInsert(
        id: id,
        dependencies: version,
        after: after,
        character: character,
      );
      operations.add(operation);
      inserted.add(operation);
      version[actorId] = counter;
      after = id;
    }
    _draft._integrate(operations);
    _pending.addAll(operations);
    _draft._notify();
    return inserted;
  }

  int _scalarIndex(List<CrdtTextInsert> atoms, int offset) {
    var position = 0;
    for (var index = 0; index < atoms.length; index++) {
      if (position == offset) return index;
      position += atoms[index].character.length;
      if (position > offset) {
        throw ArgumentError('An edit cannot split a surrogate pair.');
      }
    }
    return atoms.length;
  }
}
