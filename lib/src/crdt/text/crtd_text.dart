import 'dart:collection';

import 'package:core/src/crdt/common/logical_clock.dart';

// automerge does it this way
// using as a reference https://www.youtube.com/watch?v=Mr0a5KyD6BU

// this is how the data is stored in memory
// for disk it must be optimized further using deltas and runlength encoding
// as per the reference video
// also would be nice to be able to store these as snapshots (with latest vector clock, to skip events already applied)
class CrdtTextRow {
  final LogicalClock opId;
  final LogicalClock? insertAfterId; // null means in the begining
  final String char; // utf8 value of a single character
  LogicalClock? deletedBy;

  CrdtTextRow(this.opId, this.insertAfterId, this.char, this.deletedBy)
    : assert(char.length == 1);

  // this comparison allows for linear replays to get the latest version
  // however, its bad for compression

  static int compareRowsByRealInsertionOrder(
    CrdtTextRow key1,
    CrdtTextRow key2,
  ) {
    final id1After = key1.insertAfterId;
    final id2After = key2.insertAfterId;

    // Handle null cases - null means "insert at start"
    if (id1After == null && id2After == null) {
      return key2.opId.compareTo(key1.opId);
    } else if (id1After == null) {
      // return key2.opId.compareTo(key1.opId);
      return -1;
    } else if (id2After == null) {
      return 1;
    }

    // Both have non-null insertAfterId
    final afterComp = id1After.compareTo(id2After);
    if (afterComp != 0) {
      return afterComp;
    }

    // return 0;
    // Same insertAfterId, later opId wins (comes first) for LWW semantics
    return key2.opId.compareTo(key1.opId);
  }

  // sort by opId
  static int compareRowsByOpId(CrdtTextRow key1, CrdtTextRow key2) {
    return key1.opId.compareTo(key2.opId);
  }

  factory CrdtTextRow.fromJson(Map<String, dynamic> json) {
    return CrdtTextRow(
      LogicalClock.fromString(json['opId']),
      json['insertAfterId'] == null
          ? null
          : LogicalClock.fromString(json['insertAfterId']),
      json['char'],
      json['deletedBy'] == null
          ? null
          : LogicalClock.fromString(json['deletedBy']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'opId': opId.toString(),
      'insertAfterId': insertAfterId?.toString(),
      'char': char,
      'deletedBy': deletedBy?.toString(),
    };
  }

  @override
  String toString() {
    return '[TextRow]{opId: $opId, insertAfterId: $insertAfterId, char: $char, deletedBy: $deletedBy}';
  }
}

// tabular representation of rows
// used for storing latest resolved version
// events that come in out of order are stored out of order too?
// because loading them is in SplayTreeSet always
// this is not used for anything yet
// class TextTabularRows {
//   final List<LogicalClock> opId;
//   final List<LogicalClock?> insertAfterId;

//   final List<String> char;
//   final List<LogicalClock?> deletedBy;

//   const TextTabularRows(
//     this.opId,
//     this.insertAfterId,
//     this.char,
//     this.deletedBy,
//   );

//   TextRow getRow(int index) {
//     return TextRow(
//       opId[index],
//       insertAfterId[index],
//       char[index],
//       deletedBy[index],
//     );
//   }

//   // unsorted add... I really dont have to order it, as processed events are
//   // okay being out of order
//   // state storage can actually be using sqlite with counter+actor as primary key
//   void addRowToEnd(TextRow row) {
//     opId.add(row.opId);
//     insertAfterId.add(row.insertAfterId);
//     char.add(row.char);
//     deletedBy.add(row.deletedBy);
//   }
// }

// TODO: greatly improve efficiency by packing values with binary encoding and
// RLE encoding
class CrdtTextChange {
  final List<CrdtTextOp> ops;

  CrdtTextChange(this.ops);

  factory CrdtTextChange.fromJson(Map<String, dynamic> json) {
    return CrdtTextChange(
      (json['ops'] as List<dynamic>)
          .map((e) => CrdtTextOp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'ops': ops.map((e) => e.toJson()).toList()};
  }

  @override
  String toString() {
    return '[TextChange]{${ops.map((e) => e.toString()).join('\n')}';
  }
}

sealed class CrdtTextOp {
  const CrdtTextOp();

  LogicalClock get opId;

  Map<String, dynamic> toJson();

  factory CrdtTextOp.fromJson(Map<String, dynamic> json) {
    if (json['_op'] == CrdtTextOpInsert.type) {
      return CrdtTextOpInsert.fromJson(json);
    } else if (json['_op'] == CrdtTextOpDelete.type) {
      return CrdtTextOpDelete.fromJson(json);
    }
    throw FormatException('Invalid TextOp format', json['_op']);
  }
}

final class CrdtTextOpInsert extends CrdtTextOp {
  static const String type = 'CrdtTextOpInsert';

  @override
  final LogicalClock opId;
  final LogicalClock? insertAfterId;
  final String char;

  const CrdtTextOpInsert(this.opId, this.insertAfterId, this.char)
    : assert(char.length == 1);

  factory CrdtTextOpInsert.fromJson(Map<String, dynamic> json) {
    if (json['_op'] != type) {
      throw FormatException('Invalid TextOpInsert format', json['_op']);
    }

    return CrdtTextOpInsert(
      LogicalClock.fromString(json['opId']),
      json['insertAfterId'] == null
          ? null
          : LogicalClock.fromString(json['insertAfterId']),
      json['char'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      '_op': type,
      'opId': opId.toString(),
      'insertAfterId': insertAfterId?.toString(),
      'char': char,
    };
  }

  @override
  String toString() {
    return '[TextOpInsert]{opId: $opId, insertAfterId: $insertAfterId, char: $char}';
  }
}

@override
final class CrdtTextOpDelete extends CrdtTextOp {
  static const type = 'CrdtTextOpDelete';

  @override
  final LogicalClock opId;
  final LogicalClock deleteId;

  const CrdtTextOpDelete(this.opId, this.deleteId);

  factory CrdtTextOpDelete.fromJson(Map<String, dynamic> json) {
    if (json['_op'] != type) {
      throw FormatException('Invalid TextOpDelete format', json['_op']);
    }

    return CrdtTextOpDelete(
      LogicalClock.fromString(json['opId']),
      LogicalClock.fromString(json['deleteId']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      '_op': type,
      'opId': opId.toString(),
      'deleteId': deleteId.toString(),
    };
  }

  @override
  String toString() {
    return '[TextOpDelete]{opId: $opId, deleteId: $deleteId}';
  }
}

// I need a stateful resolver, which will keep track of the cursor position
// and will batch the events into changes, which must be flushed to the server.

class QEntryItem extends DoubleLinkedQueueEntry<String> {
  final String char; // single character...

  QEntryItem(this.char) : super(char);

  @override
  String toString() => char;
}

// there is rows storeage

class CrdtTextStorage {
  final SplayTreeSet<CrdtTextRow> _rows;

  CrdtTextStorage(List<CrdtTextRow> initialRows)
    : _rows = SplayTreeSet<CrdtTextRow>(CrdtTextRow.compareRowsByOpId)
        ..addAll(initialRows);

  // events will mutate the rows
}

class CrdtTextTable with Iterable<CrdtTextRow>, SetBase<CrdtTextRow> {
  final List<CrdtTextRow> _rows;

  const CrdtTextTable(List<CrdtTextRow> initialRows) : _rows = initialRows;

  @override
  Iterator<CrdtTextRow> get iterator => _rows.iterator;

  bool _hasTheValue(CrdtTextRow v) {
    for (final row in _rows) {
      if (row.opId == v.opId) {
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
      if (row.opId == value.insertAfterId) {
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
    throw Exception('We are never removing');
    // TODO: implement remove
    // throw UnimplementedError();
  }
}

class CrdtTextResolver {
  final CrdtTextTable rows;
  // final SplayTreeSet<CrdtTextRow> rows;

  CrdtTextResolver(List<CrdtTextRow> initialRows)
    // : rows = SplayTreeSet<CrdtTextRow>(
    //     CrdtTextRow.compareRowsByRealInsertionOrder,
    //   )..addAll(initialRows);
    : rows = CrdtTextTable(initialRows);

  void handleChange(CrdtTextChange change) {
    for (final op in change.ops) {
      handleOp(op);
    }
  }

  void handleOp(CrdtTextOp op) {
    switch (op) {
      case CrdtTextOpInsert insertEvent:
        rows.add(
          CrdtTextRow(
            insertEvent.opId,
            insertEvent.insertAfterId,
            insertEvent.char,
            null,
          ),
        );

        break;
      case CrdtTextOpDelete deleteEvent:
        final rowToDelete = rows.firstWhere(
          (row) => row.opId == deleteEvent.deleteId,
        );
        rowToDelete.deletedBy = deleteEvent.opId;

        break;
    }
  }

  int getCursorIndexAtOpId(LogicalClock opId) {
    int index = 0;
    for (final row in rows) {
      if (row.opId == opId) return index;
      if (row.deletedBy != null) index++;
    }

    throw Exception('OpId $opId is not in the text. Maximum index $index');
  }

  LogicalClock? getOpIdAtCursorIndex(int atIndex) {
    if (atIndex == 0) {
      return null;
    }

    int index = 0;
    // otherwise do like the rebuildings
    for (final row in rows) {
      if (row.deletedBy != null) {
        continue;
      }

      index++;
      if (index == atIndex) {
        return row.opId;
      }
    }

    throw Exception(
      'Text index $atIndex is out of bounds. Maximum index $index',
    );
  }

  int debugGetResolvedTextLength() {
    int length = 0;

    // otherwise do like the rebuildings
    for (final row in rows) {
      if (row.deletedBy == null) {
        length++;
      }
    }

    return length;
  }

  /// returns text content upto maxLen.
  /// if maxLen is null, returns full content.
  String getTextContentLatest({int? maxLen}) {
    final content = StringBuffer();
    for (final row in rows) {
      if (maxLen != null && content.length == maxLen) {
        break;
      }

      // print("iterating over $row");
      if (row.deletedBy == null) {
        content.write(row.char);
      }
    }
    return content.toString();
  }

  String debugGetContentAtVector(VectorLogicalClock vector) {
    final content = StringBuffer();
    for (final node in rows) {
      if (!vector.isVisible(node.opId)) {
        continue;
      }
      // deleted could have been not visible also
      if (node.deletedBy == null || !vector.isVisible(node.deletedBy!)) {
        content.write(node.char);
      }
    }
    return content.toString();
  }
}

// thats how it could be stored?
class CrdtTextSnapshot {
  final List<CrdtTextRow> rows;
  // this is not needed, could be resolved from the rows
  // stored as optimization technique
  final VectorLogicalClock vectorClock;

  CrdtTextSnapshot(this.rows, this.vectorClock);

  factory CrdtTextSnapshot.evaluateVectorClock(List<CrdtTextRow> rows) {
    final vc = VectorLogicalClock.empty();

    for (final row in rows) {
      vc.logicalClockUpdate(row.opId);
    }

    return CrdtTextSnapshot(rows, vc);
  }
}

// this is the value which is stored on the class
// this is a stateful representation of the text
// this return a Cursor, and it manages local operations
// creates changes to be sent off
// creates snapshots for storage. Usually they should be split into parts
// for now, full data is encapsulated
// deals with the vectorClock
// cursor is the ONLY way to insert values into the crdt text
// cursor functionalities are built-in here
// cursor begins at the start of the text
class CrdtText {
  final Actor thisActorId;
  final CrdtTextResolver resolver;
  final VectorLogicalClock vectorClock;
  final LogicalClockGenerator thisGen;

  // local change should be accumulated as the user types
  // it should be flusheable with fixed timestamps
  // so the actual timestamp is in range?
  final void Function(CrdtTextChange) flushLocalChanges;
  final List<CrdtTextOp> localChanges = [];

  int cursorIndex = 0;
  LogicalClock? cursorOpId;

  CrdtText(
    this.thisActorId,
    this.resolver,
    this.vectorClock,
    this.flushLocalChanges,
  ) : thisGen = LogicalClockGenerator(vectorClock, thisActorId);

  factory CrdtText.fromSnapshot(
    Actor thisActorId,
    void Function(CrdtTextChange) flushLocalChanges,
    CrdtTextSnapshot snapshot,
  ) {
    final resolver = CrdtTextResolver(snapshot.rows);
    final vectorClock = snapshot.vectorClock;
    return CrdtText(thisActorId, resolver, vectorClock, flushLocalChanges);
  }

  void onExternalChange(CrdtTextChange change) {
    // how many characters were inserted/deleted before the cursor
    // this is a relative offset
    // only matters if the current value was not deleted.
    // this is completely unimplemented now
    int beforeCursorDelta = 0;

    // brute force update the vector clock for each one of the changes
    for (final op in change.ops) {
      vectorClock.logicalClockUpdate(op.opId);

      switch (op) {
        case CrdtTextOpInsert insertOp:
          //hmmm was it before or not?
          beforeCursorDelta += 0;

          break;
        case CrdtTextOpDelete deleteOp:
          beforeCursorDelta -= 0;

          break;
      }
    }
    // apply to the resolver
    resolver.handleChange(change);

    // flush local changes?
    _flushLocalChanges();

    // update the cursor if the change happened before it
    // how to know if it happened before it?

    // TODO: also check that the actual cursor value was not overwritten
    // if it was, then the cursor needs a complete rebuild
    if (beforeCursorDelta != 0) {
      // cursor.applyBeforePositionDelta(beforeCursorDelta);
    }
    throw Exception('TODO');
  }

  // vector clocks are handled transparently
  void insertAtCursor(String char) {
    // get the logical clock
    final opId = thisGen.next();

    final insertOp = CrdtTextOpInsert(opId, cursorOpId, char);
    _onLocalChange(insertOp);

    cursorIndex++;
    cursorOpId = opId;
  }

  /// hitting backspace key, removing char before cursor
  void backspaceAtCurstor() {
    final opId = thisGen.next();

    if (cursorOpId == null || cursorIndex == 0) {
      throw Exception(
        'Cannot backspace at the begginging of the text. cursorPosition $cursorIndex, cursorOpId $cursorOpId',
      );
    }

    final deleteOp = CrdtTextOpDelete(opId, cursorOpId!);
    _onLocalChange(deleteOp);

    // very unperformant way to get previous position
    cursorIndex--;
    cursorOpId = resolver.getOpIdAtCursorIndex(cursorIndex);

    // need to get the new value under the cursor
  }

  /// hitting del key, removing char after cursor
  void delAtCursor() {
    final opId = thisGen.next();

    // get the next opId, very slow
    final afterCursorOpId = resolver.getOpIdAtCursorIndex(cursorIndex + 1);

    if (afterCursorOpId == null) {
      throw Exception('Should never happen, ever ever ever');
    }

    final deleteOp = CrdtTextOpDelete(opId, afterCursorOpId);
    _onLocalChange(deleteOp);

    // cursor position and cursorOpId did not change
  }

  /// relocating cursor to a new positoin
  void moveCursor(int toIndex) {
    cursorIndex = toIndex;
    cursorOpId = resolver.getOpIdAtCursorIndex(cursorIndex);
  }

  int debugGetResolvedLength() {
    return resolver.debugGetResolvedTextLength();
  }

  // this is happening every time a keystroke is done
  void _onLocalChange(CrdtTextOp op) {
    // print('handling local change $op');
    resolver.handleOp(op);
    localChanges.add(op);
  }

  void _flushLocalChanges() {
    flushLocalChanges(CrdtTextChange(localChanges));
    localChanges.clear();
  }

  /// will return the contents of the given
  String getContent({int? maxLen}) {
    return resolver.getTextContentLatest(maxLen: maxLen);
  }

  CrdtTextSnapshot getLatestSnapshot() {
    return CrdtTextSnapshot(resolver.rows.toList(), vectorClock);
  }
}

class TestChangeFlusher {
  List<CrdtTextChange> changes = [];

  TestChangeFlusher();

  void flushLocalChanges(CrdtTextChange change) {
    changes.add(change);
  }
}
