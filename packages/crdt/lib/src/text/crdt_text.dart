library;

part 'crdt_text_binding.dart';
part 'crdt_text_change.dart';
part 'crdt_text_controller.dart';
part 'crdt_text_exception.dart';
part 'crdt_text_id.dart';
part 'crdt_text_json.dart';
part 'crdt_text_operation.dart';

/// Mutable RGA text with causal events and explicit save acknowledgment.
///
/// Each independent writer must use a distinct [actorId]. Offsets are UTF-16
/// positions; edits must fall on Unicode scalar boundaries. Delivery must be
/// causal: [applyChange] rejects missing dependencies without buffering.
final class CrdtText {
  final String actorId;
  Map<CrdtTextId, CrdtTextOperation> _operations = {};
  Map<String, int> _version = {};
  final List<CrdtTextOperation> _pending = [];
  CrdtTextChange? _prepared;
  final List<void Function()> _listeners = [];

  CrdtText({required this.actorId}) {
    _requireActor(actorId);
  }

  /// Restores the same writer, including edits awaiting acknowledgment.
  factory CrdtText.fromJson(Object? json) => _parseJson(() {
    final map = _jsonMap(json);
    _checkJsonVersion(map);
    final result = CrdtText(actorId: _jsonString(map['actorId']));
    final operations = _jsonList(
      map['operations'],
    ).map(CrdtTextOperation.fromJson).toList();
    if (operations.map((operation) => operation.id).toSet().length !=
        operations.length) {
      throw const FormatException('Snapshot contains duplicate operation IDs.');
    }
    operations.sort((left, right) => left.id.compareTo(right.id));
    result._integrate(operations);

    final pending = _jsonList(map['pending']).map(CrdtTextId.fromJson).toList();
    final own = operations
        .where((operation) => operation.id.actorId == result.actorId)
        .toList();
    if (pending.length > own.length ||
        !_sameList(
          pending,
          own.skip(own.length - pending.length).map((op) => op.id).toList(),
        )) {
      throw const FormatException(
        'Pending edits must be a suffix of own edits.',
      );
    }
    result._pending.addAll(own.skip(own.length - pending.length));
    if (!map.containsKey('prepared')) {
      throw const FormatException('Missing prepared save state.');
    }
    if (map['prepared'] != null) {
      final prepared = CrdtTextChange.fromJson(map['prepared']);
      if (prepared.operations.length > result._pending.length ||
          !_sameList(
            prepared.operations,
            result._pending.take(prepared.operations.length).toList(),
          )) {
        throw const FormatException(
          'Prepared edits must prefix pending edits.',
        );
      }
      result._prepared = prepared;
    }
    return result;
  });

  String get text => _visibleAtoms().map((atom) => atom.character).join();

  /// The UTF-16 length, matching Dart strings and editor offsets.
  int get length => text.length;

  bool get hasPendingChanges => _pending.isNotEmpty;

  void insert(int offset, String text) => replace(offset, offset, text);

  void delete(int start, int end) => replace(start, end, '');

  /// Replaces [start] through the exclusive [end] as one local mutation.
  void replace(int start, int end, String text) {
    final atoms = _visibleAtoms();
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

  /// Applies a complete causal batch, ignoring exact retransmissions.
  ///
  /// Throws [CrdtTextException] before mutation if any operation is invalid.
  /// Replayed operations never become local pending edits.
  void applyChange(CrdtTextChange change) {
    if (change.actorId == actorId &&
        _pending.isNotEmpty &&
        change.operations.any(
          (operation) => !_operations.containsKey(operation.id),
        )) {
      throw const CrdtTextException(
        'Another writer cannot extend this actor while local edits are pending.',
      );
    }
    if (_integrate(change.operations)) _notify();
  }

  /// Captures unsaved edits; repeated calls return the same batch until saved.
  CrdtTextChange? prepareChange() {
    if (_prepared != null) return _prepared;
    if (_pending.isEmpty) return null;
    return _prepared = CrdtTextChange(_pending);
  }

  /// Acknowledges only the currently prepared batch after durable persistence.
  void acknowledgeChange(CrdtTextChange change) {
    if (_prepared == null || _prepared != change) {
      throw ArgumentError(
        'Only the currently prepared change can be acknowledged.',
      );
    }
    _pending.removeRange(0, change.operations.length);
    _prepared = null;
  }

  /// Exports detached JSON without advancing the saved boundary.
  Map<String, Object?> toJson() {
    final operations = _operations.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return {
      'version': 1,
      'actorId': actorId,
      'operations': operations.map((operation) => operation.toJson()).toList(),
      'pending': _pending.map((operation) => operation.id.toJson()).toList(),
      'prepared': _prepared?.toJson(),
    };
  }

  /// Observes accepted edits synchronously, after the full mutation commits.
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }

  List<CrdtTextInsert> _replaceIds(
    List<CrdtTextId> targets,
    CrdtTextId? after,
    String replacement,
  ) {
    final characters = _scalars(replacement);
    final count = targets.length + characters.length;
    if (count == 0) return [];
    var counter = _greatestCounter(_version);
    if (count > _maxCounter - counter) {
      throw StateError('The document has exhausted its exact JSON counters.');
    }
    final version = Map<String, int>.of(_version);
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
    _integrate(operations);
    _pending.addAll(operations);
    _notify();
    return inserted;
  }

  bool _integrate(Iterable<CrdtTextOperation> incoming) {
    final operations = Map<CrdtTextId, CrdtTextOperation>.of(_operations);
    final version = Map<String, int>.of(_version);
    var changed = false;
    for (final operation in incoming) {
      final existing = operations[operation.id];
      if (existing != null) {
        if (existing != operation) {
          throw const CrdtTextException(
            'An operation ID has conflicting content.',
          );
        }
        continue;
      }
      final dependencies = operation.dependencies;
      if (operation.id.counter != _greatestCounter(dependencies) + 1) {
        throw const CrdtTextException('Invalid Lamport counter.');
      }
      if ((version[operation.id.actorId] ?? 0) !=
          (dependencies[operation.id.actorId] ?? 0)) {
        throw const CrdtTextException(
          'An actor operation arrived out of order.',
        );
      }
      for (final entry in dependencies.entries) {
        final dependency =
            operations[CrdtTextId(actorId: entry.key, counter: entry.value)];
        if (dependency == null) {
          throw const CrdtTextException('A causal dependency is missing.');
        }
        for (final ancestor in dependency.dependencies.entries) {
          if ((dependencies[ancestor.key] ?? 0) < ancestor.value) {
            throw const CrdtTextException(
              'Causal dependencies are not closed.',
            );
          }
        }
      }
      final reference = switch (operation) {
        CrdtTextInsert() => operation.after,
        CrdtTextDelete() => operation.target,
      };
      if (reference != null &&
          (operations[reference] is! CrdtTextInsert ||
              (dependencies[reference.actorId] ?? 0) < reference.counter)) {
        throw const CrdtTextException(
          'An edit must reference an observed insertion.',
        );
      }
      operations[operation.id] = operation;
      version[operation.id.actorId] = operation.id.counter;
      changed = true;
    }
    if (changed) {
      _operations = operations;
      _version = version;
    }
    return changed;
  }

  Set<CrdtTextId> _deletedIds() => _operations.values
      .whereType<CrdtTextDelete>()
      .map((operation) => operation.target)
      .toSet();

  List<CrdtTextInsert> _orderedAtoms() {
    final children = <CrdtTextId?, List<CrdtTextInsert>>{};
    for (final operation in _operations.values.whereType<CrdtTextInsert>()) {
      children.putIfAbsent(operation.after, () => []).add(operation);
    }
    for (final siblings in children.values) {
      siblings.sort((left, right) => right.id.compareTo(left.id));
    }
    final stack = (children[null] ?? []).reversed.toList();
    final result = <CrdtTextInsert>[];
    while (stack.isNotEmpty) {
      final atom = stack.removeLast();
      result.add(atom);
      stack.addAll((children[atom.id] ?? []).reversed);
    }
    return result;
  }

  List<CrdtTextInsert> _visibleAtoms() {
    final deleted = _deletedIds();
    return _orderedAtoms().where((atom) => !deleted.contains(atom.id)).toList();
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
