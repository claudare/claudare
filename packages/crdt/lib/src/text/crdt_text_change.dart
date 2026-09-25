part of 'crdt_text.dart';

/// An immutable batch from one writer, suitable for a JSON event log.
final class CrdtTextChange {
  final List<CrdtTextOperation> operations;

  CrdtTextChange(Iterable<CrdtTextOperation> operations)
    : operations = List.unmodifiable(operations) {
    if (this.operations.isEmpty) {
      throw ArgumentError('A text change must contain operations.');
    }
    if (this.operations.any((operation) => operation.id.actorId != actorId)) {
      throw ArgumentError('A text change must have exactly one author.');
    }
  }

  String get actorId => operations.first.id.actorId;

  factory CrdtTextChange.fromJson(Object? json) => _parseJson(() {
    final map = _jsonMap(json);
    _checkJsonVersion(map);
    return CrdtTextChange(
      _jsonList(map['operations']).map(CrdtTextOperation.fromJson),
    );
  });

  Map<String, Object?> toJson() => {
    'version': 1,
    'operations': operations.map((operation) => operation.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is CrdtTextChange && _sameList(operations, other.operations);

  @override
  int get hashCode => Object.hashAll(operations);
}
