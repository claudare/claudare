import '../common/logical_clock.dart';
import '../common/vector_logical_clock.dart';
import 'crdt_text_change.dart';
import 'crdt_text_operation.dart';
import 'crdt_text_row.dart';
import 'crdt_text_table.dart';

class CrdtTextResolver {
  final CrdtTextTable table;

  CrdtTextResolver(List<CrdtTextRow> rows) : table = CrdtTextTable(rows);

  CrdtTextResolver.fromChanges(List<CrdtTextChange> changes)
    : table = CrdtTextTable([]) {
    for (final change in changes) {
      handleChange(change);
    }
  }

  void handleChange(CrdtTextChange change) {
    for (final operation in change.operations) {
      handleOperation(operation);
    }
  }

  void handleOperation(CrdtTextOperation operation) {
    switch (operation) {
      case CrdtTextOperationInsert insertOperation:
        table.add(
          CrdtTextRow(
            insertOperation.operationId,
            insertOperation.insertAfterId,
            insertOperation.char,
            null,
          ),
        );

        break;
      case CrdtTextOperationDelete deleteOperation:
        final rowToDelete = table.firstWhere(
          (row) => row.operationId == deleteOperation.deleteId,
        );
        rowToDelete.deletedBy = deleteOperation.operationId;

        break;
    }
  }

  // int getIndexAtOperationId(LogicalClock operationId) {
  //   int index = 0;
  //   for (final row in table) {
  //     if (row.operationId == operationId) return index;
  //     if (row.deletedBy != null) index++;
  //   }

  //   throw Exception(
  //     'OperationId $operationId is not in the text. Maximum index $index',
  //   );
  // }

  LogicalClock? getOperationIdAtIndex(int atIndex) {
    if (atIndex == 0) {
      return null;
    }

    int index = 0;

    for (final row in table) {
      if (row.deletedBy != null) {
        continue;
      }

      index++;
      if (index == atIndex) {
        return row.operationId;
      }
    }

    throw Exception(
      'Text index $atIndex is out of bounds. Maximum index $index',
    );
  }

  int debugGetResolvedTextLength() {
    int length = 0;

    // otherwise do like the rebuildings
    for (final row in table) {
      if (row.deletedBy == null) {
        length++;
      }
    }

    return length;
  }

  /// returns text content this is slow, and should only be used for
  /// debugging or testing
  String resolveToStringSlow() {
    final content = StringBuffer();
    for (final row in table) {
      // print("iterating over $row");
      if (row.deletedBy == null) {
        content.write(row.char);
      }
    }
    return content.toString();
  }

  String debugGetContentAtVector(VectorLogicalClock vector) {
    final content = StringBuffer();
    for (final node in table) {
      if (!vector.isVisible(node.operationId)) {
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
