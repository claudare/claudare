import 'dart:collection' show SetBase;

import 'crdt_text_row.dart';

class CrdtTextTable with Iterable<CrdtTextRow>, SetBase<CrdtTextRow> {
  final List<CrdtTextRow> _rows;

  const CrdtTextTable(List<CrdtTextRow> initialRows) : _rows = initialRows;

  @override
  Iterator<CrdtTextRow> get iterator => _rows.iterator;

  bool _hasTheValue(CrdtTextRow v) {
    for (final row in _rows) {
      if (row.operationId == v.operationId) {
        return true;
      }
    }
    return false;
  }

  // should return false if value was already in the set...
  // true if in the set
  // TODO: this is super-duper inefficient, just prototyping
  @override
  bool add(CrdtTextRow value) {
    final alreadyExists = _hasTheValue(value);
    if (alreadyExists) {
      return false;
    }

    if (value.insertAfterId == null) {
      // insert in the front
      _rows.insert(0, value);

      return true;
    }

    int insertIndex = 1;
    bool found = false;

    for (final row in _rows) {
      if (row.operationId == value.insertAfterId) {
        found = true;
        break;
      }
      insertIndex++;
    }

    if (!found) {
      throw Exception('Failed to find insert after for $value');
    }

    if (insertIndex == _rows.length) {
      _rows.add(value);
    } else {
      _rows.insert(insertIndex, value);
    }

    return true;
  }

  @override
  CrdtTextRow? lookup(Object? element) {
    if (element == null) {
      return null;
    }

    // eh?
    final contains = _rows.contains(element);

    if (contains) {
      final typed = element as CrdtTextRow;
      return typed;
    }
    return null;
  }

  @override
  bool remove(Object? value) {
    throw Exception('Never remove');
  }
}
