// this is how the data is stored in memory
// for disk it must be optimized further using deltas and runlength encoding
// as per the reference video
// also would be nice to be able to store these as snapshots (with latest vector clock, to skip events already applied)
import 'package:core/src/crdt/common/logical_clock.dart';

class CrdtTextRow {
  final LogicalClock operationId;
  final LogicalClock? insertAfterId; // null means in the begining
  final String char; // utf8 value of a single character
  LogicalClock? deletedBy;

  CrdtTextRow(this.operationId, this.insertAfterId, this.char, this.deletedBy)
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
      return key2.operationId.compareTo(key1.operationId);
    } else if (id1After == null) {
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
    return key2.operationId.compareTo(key1.operationId);
  }

  // sort by opId
  static int compareRowsByOpId(CrdtTextRow key1, CrdtTextRow key2) {
    return key1.operationId.compareTo(key2.operationId);
  }

  factory CrdtTextRow.fromJson(Map<String, dynamic> json) {
    return CrdtTextRow(
      LogicalClock.fromString(json['operationId']),
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
      'operationId': operationId.toString(),
      'insertAfterId': insertAfterId?.toString(),
      'char': char,
      'deletedBy': deletedBy?.toString(),
    };
  }

  @override
  String toString() {
    return '[TextRow]{operationId: $operationId, insertAfterId: $insertAfterId, char: $char, deletedBy: $deletedBy}';
  }
}
