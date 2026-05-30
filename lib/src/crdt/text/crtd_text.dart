import '../common/logical_clock.dart';
import '../common/logical_clock_generator.dart';
import '../common/vector_logical_clock.dart';

import 'crdt_text_change.dart';
import 'crdt_text_operation.dart';
import 'crdt_text_snapshot.dart';
import 'crdt_text_resolver.dart';

// automerge does it this way
// using as a reference https://www.youtube.com/watch?v=Mr0a5KyD6BU

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
// TODO: dont use cursor, and instead diff the full text?
// Thanks to Martin Kleppmann! https://www.youtube.com/watch?v=Mr0a5KyD6BU
class CrdtText {
  final Actor thisActorId;
  final CrdtTextResolver resolver;
  final VectorLogicalClock vectorClock;
  final LogicalClockGenerator operationIdGenerator;

  // local change should be accumulated as the user types
  // it should be flusheable with fixed timestamps
  // so the actual timestamp is in range?
  final void Function(CrdtTextChange) flushLocalChanges;
  final List<CrdtTextOperation> localChanges = [];

  int cursorIndex = 0;
  LogicalClock? cursorOpId;

  CrdtText(
    this.thisActorId,
    this.resolver,
    this.vectorClock,
    this.flushLocalChanges,
  ) : operationIdGenerator = LogicalClockGenerator(vectorClock, thisActorId);

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
    for (final op in change.operations) {
      vectorClock.mergeLogicalClockMutate(op.operationId);

      switch (op) {
        case CrdtTextOperationInsert insertOp:
          //hmmm was it before or not?
          beforeCursorDelta += 0;

          break;
        case CrdtTextOperationDelete deleteOp:
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
    final operationId = operationIdGenerator.next();

    final insertOp = CrdtTextOperationInsert(operationId, cursorOpId, char);
    _onLocalChange(insertOp);

    cursorIndex++;
    cursorOpId = operationId;
  }

  /// hitting backspace key, removing char before cursor
  void backspaceAtCurstor() {
    final opId = operationIdGenerator.next();

    if (cursorOpId == null || cursorIndex == 0) {
      throw Exception(
        'Cannot backspace at the begginging of the text. cursorPosition $cursorIndex, cursorOpId $cursorOpId',
      );
    }

    final deleteOp = CrdtTextOperationDelete(opId, cursorOpId!);
    _onLocalChange(deleteOp);

    // very unperformant way to get previous position
    cursorIndex--;
    cursorOpId = resolver.getOperationIdAtIndex(cursorIndex);

    // need to get the new value under the cursor
  }

  /// hitting del key, removing char after cursor
  void delAtCursor() {
    final opId = operationIdGenerator.next();

    // get the next opId, very slow
    final afterCursorOpId = resolver.getOperationIdAtIndex(cursorIndex + 1);

    if (afterCursorOpId == null) {
      throw Exception('Should never happen, ever ever ever');
    }

    final deleteOp = CrdtTextOperationDelete(opId, afterCursorOpId);
    _onLocalChange(deleteOp);

    // cursor position and cursorOpId did not change
  }

  /// relocating cursor to a new positoin
  void moveCursor(int toIndex) {
    cursorIndex = toIndex;
    cursorOpId = resolver.getOperationIdAtIndex(cursorIndex);
  }

  int debugGetResolvedLength() {
    return resolver.debugGetResolvedTextLength();
  }

  // this is happening every time a keystroke is done
  void _onLocalChange(CrdtTextOperation op) {
    // print('handling local change $op');
    resolver.handleOperation(op);
    localChanges.add(op);
  }

  void _flushLocalChanges() {
    flushLocalChanges(CrdtTextChange(localChanges));
    localChanges.clear();
  }

  /// returns full text content
  /// this is slow
  String getContent() {
    return resolver.resolveToStringSlow();
  }

  CrdtTextSnapshot getLatestSnapshot() {
    return CrdtTextSnapshot(resolver.table.toList(), vectorClock);
  }
}

class TestChangeFlusher {
  List<CrdtTextChange> changes = [];

  TestChangeFlusher();

  void flushLocalChanges(CrdtTextChange change) {
    changes.add(change);
  }
}
