import 'package:core/src/crdt/common/vector_logical_clock.dart';
import 'package:core/src/crdt/text/crdt_text_row.dart';

/// [CrdtTextSnapshot] is a snapshot of the resolved list of rows.
/// A projection produces this from events containing changes.
/// It would be nice to also store a String value of the CrdtText...
class CrdtTextSnapshot {
  final List<CrdtTextRow> rows; // resolved rows
  // this is not needed, could be resolved from the rows
  // stored as optimization technique
  final VectorLogicalClock vectorClock;

  const CrdtTextSnapshot(this.rows, this.vectorClock);

  factory CrdtTextSnapshot.withoutVectorClock(List<CrdtTextRow> rows) {
    final vc = VectorLogicalClock.empty();

    for (final row in rows) {
      vc.mergeLogicalClockMutate(row.operationId);
    }

    return CrdtTextSnapshot(rows, vc);
  }
}
