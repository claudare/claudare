part of 'crdt_text.dart';

/// An immutable edit and the causal state observed by its author.
sealed class CrdtTextOperation {
  final CrdtTextId id;
  final Map<String, int> dependencies;

  CrdtTextOperation({required this.id, required Map<String, int> dependencies})
    : dependencies = Map.unmodifiable(dependencies) {
    for (final entry in dependencies.entries) {
      _requireActor(entry.key);
      _requireCounter(entry.value);
    }
  }

  factory CrdtTextOperation.fromJson(Object? json) => _parseJson(() {
    final map = _jsonMap(json);
    final id = CrdtTextId.fromJson(map['id']);
    final dependencies = _jsonMap(
      map['dependencies'],
    ).map((key, value) => MapEntry(key, _jsonInt(value)));
    return switch (map['kind']) {
      'insert' => CrdtTextInsert(
        id: id,
        dependencies: dependencies,
        after: map['after'] == null ? null : CrdtTextId.fromJson(map['after']),
        character: _jsonString(map['character']),
      ),
      'delete' => CrdtTextDelete(
        id: id,
        dependencies: dependencies,
        target: CrdtTextId.fromJson(map['target']),
      ),
      _ => throw const FormatException('Unknown text operation kind.'),
    };
  });

  Map<String, Object?> toJson();

  Map<String, Object?> _jsonBase(String kind) => {
    'kind': kind,
    'id': id.toJson(),
    'dependencies': {
      for (final actor in dependencies.keys.toList()..sort())
        actor: dependencies[actor],
    },
  };

  bool _sameBase(CrdtTextOperation other) =>
      id == other.id && _sameMap(dependencies, other.dependencies);

  int get _baseHash => Object.hash(
    id,
    Object.hashAllUnordered(
      dependencies.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Inserts one Unicode scalar after [after], or at the head when it is null.
final class CrdtTextInsert extends CrdtTextOperation {
  final CrdtTextId? after;
  final String character;

  CrdtTextInsert({
    required super.id,
    required super.dependencies,
    required this.character,
    this.after,
  }) {
    if (_scalars(character).length != 1) {
      throw ArgumentError('An insertion must contain one Unicode scalar.');
    }
  }

  @override
  Map<String, Object?> toJson() => {
    ..._jsonBase('insert'),
    'after': after?.toJson(),
    'character': character,
  };

  @override
  bool operator ==(Object other) =>
      other is CrdtTextInsert &&
      _sameBase(other) &&
      after == other.after &&
      character == other.character;

  @override
  int get hashCode => Object.hash(_baseHash, after, character);
}

/// Hides an insertion while retaining it as an anchor for other edits.
final class CrdtTextDelete extends CrdtTextOperation {
  final CrdtTextId target;

  CrdtTextDelete({
    required super.id,
    required super.dependencies,
    required this.target,
  });

  @override
  Map<String, Object?> toJson() => {
    ..._jsonBase('delete'),
    'target': target.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CrdtTextDelete && _sameBase(other) && target == other.target;

  @override
  int get hashCode => Object.hash(_baseHash, target);
}
