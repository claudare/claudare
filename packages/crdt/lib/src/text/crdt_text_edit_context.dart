part of 'crdt_text.dart';

/// A private editing draft with an actor and explicit save acknowledgment.
///
/// Copies the supplied document. Deliver subsequent changes with [applyChange]
/// and apply saved changes separately to the original document. Each independent
/// writer must use a distinct [actorId]. Pending edits exist only in memory.
final class CrdtTextEditContext {
  final String actorId;
  final CrdtText _draft;
  final List<CrdtTextOperation> _pending = [];
  CrdtTextChange? _prepared;

  CrdtTextEditContext({required CrdtText document, required this.actorId})
    : _draft = document.fork() {
    _requireActor(actorId);
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

  /// Applies incoming changes to the draft without creating pending edits.
  ///
  /// Exact echoes do not acknowledge edits. Throws [CrdtTextException] before
  /// mutation for invalid changes or another writer extending this actor while
  /// local edits are pending.
  void applyChange(CrdtTextChange change) {
    if (change.actorId == actorId &&
        _pending.isNotEmpty &&
        change.operations.any(
          (operation) => !_draft._operations.containsKey(operation.id),
        )) {
      throw const CrdtTextException(
        'Another writer cannot extend this actor while local edits are pending.',
      );
    }
    _draft.applyChange(change);
  }

  /// Captures unsaved edits; repeated calls return the same batch until saved.
  CrdtTextChange? prepareChange() {
    if (_prepared != null) return _prepared;
    if (_pending.isEmpty) return null;
    return _prepared = CrdtTextChange(_pending);
  }

  /// Clears only the prepared batch after the caller has persisted it.
  ///
  /// Does not apply changes to the original document or notify text listeners.
  void acknowledgeChange(CrdtTextChange change) {
    if (_prepared == null || _prepared != change) {
      throw ArgumentError(
        'Only the currently prepared change can be acknowledged.',
      );
    }
    _pending.removeRange(0, change.operations.length);
    _prepared = null;
  }

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
