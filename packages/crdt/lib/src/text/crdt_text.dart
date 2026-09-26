library;

import 'package:crdt/crdt_text.dart';

part 'crdt_text_binding.dart';
part 'crdt_text_change.dart';
part 'crdt_text_controller.dart';
part 'crdt_text_edit_context.dart';
part 'crdt_text_exception.dart';
part 'crdt_text_id.dart';
part 'crdt_text_helpers.dart';
part 'crdt_text_operation.dart';
part 'crdt_text_test_utils.dart';

/// Mutable RGA document state, independent of the actor editing it.
///
/// Use [CrdtTextEditContext] to create changes. Delivery must be causal:
/// [applyChange] rejects missing dependencies without buffering.
final class CrdtText {
  Map<CrdtTextId, CrdtTextOperation> _operations = {};
  Map<String, int> _version = {};
  final List<void Function()> _listeners = [];

  CrdtText();

  CrdtText._copy(CrdtText document)
    : _operations = Map.of(document._operations),
      _version = Map.of(document._version);

  /// Copies document history into independent state without copying listeners.
  CrdtText fork() => CrdtText._copy(this);

  /// Restores document history without selecting a writer.
  factory CrdtText.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    final result = CrdtText();
    final operations = (map['operations'] as List)
        .map(CrdtTextOperation.fromJson)
        .toList();
    if (operations.map((operation) => operation.id).toSet().length !=
        operations.length) {
      throw const FormatException('Snapshot contains duplicate operation IDs.');
    }
    operations.sort((left, right) => left.id.compareTo(right.id));
    result._integrate(operations);

    return result;
  }

  String get text => _visibleAtoms().map((atom) => atom.character).join();

  /// The UTF-16 length, matching Dart strings and editor offsets.
  int get length => text.length;

  /// Applies a complete causal batch, ignoring exact retransmissions.
  ///
  /// Throws [CrdtTextException] before mutation if any operation is invalid.
  void applyChange(CrdtTextChange change) {
    if (_integrate(change.operations)) _notify();
  }

  /// Exports detached document history without local editing state.
  Map<String, Object?> toJson() {
    final operations = _operations.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return {
      'operations': operations.map((operation) => operation.toJson()).toList(),
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
}
