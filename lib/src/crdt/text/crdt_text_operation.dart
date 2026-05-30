import 'package:core/src/crdt/common/logical_clock.dart';

sealed class CrdtTextOperation {
  const CrdtTextOperation();

  LogicalClock get operationId;

  Map<String, dynamic> toJson();

  factory CrdtTextOperation.fromJson(Map<String, dynamic> json) {
    if (json['type'] == CrdtTextOperationInsert.type) {
      return CrdtTextOperationInsert.fromJson(json);
    } else if (json['type'] == CrdtTextOperationDelete.type) {
      return CrdtTextOperationDelete.fromJson(json);
    }
    throw FormatException('Invalid TextOp format', json['type']);
  }
}

final class CrdtTextOperationInsert extends CrdtTextOperation {
  static const String type = 'CrdtTextOperationInsert';

  @override
  final LogicalClock operationId;
  final LogicalClock? insertAfterId;
  final String char;

  const CrdtTextOperationInsert(this.operationId, this.insertAfterId, this.char)
    : assert(char.length == 1);

  factory CrdtTextOperationInsert.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw FormatException('Invalid TextOpInsert format', json['type']);
    }

    return CrdtTextOperationInsert(
      LogicalClock.fromString(json['operationId']),
      json['insertAfterId'] == null
          ? null
          : LogicalClock.fromString(json['insertAfterId']),
      json['char'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'operationId': operationId.toString(),
      'insertAfterId': insertAfterId?.toString(),
      'char': char,
    };
  }

  @override
  String toString() {
    return '[$type]{operationId: $operationId, insertAfterId: $insertAfterId, char: $char}';
  }
}

final class CrdtTextOperationDelete extends CrdtTextOperation {
  static const type = 'CrdtTextOperationDelete';

  @override
  final LogicalClock operationId;
  final LogicalClock deleteId;

  const CrdtTextOperationDelete(this.operationId, this.deleteId);

  factory CrdtTextOperationDelete.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw FormatException('Invalid TextOpDelete format', json['type']);
    }

    return CrdtTextOperationDelete(
      LogicalClock.fromString(json['operationId']),
      LogicalClock.fromString(json['deleteId']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'operationId': operationId.toString(),
      'deleteId': deleteId.toString(),
    };
  }

  @override
  String toString() {
    return '[$type]{operationId: $operationId, deleteId: $deleteId}';
  }
}
