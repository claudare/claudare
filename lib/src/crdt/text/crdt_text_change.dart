import 'package:core/src/crdt/text/crdt_text_operation.dart';

// TODO: greatly improve efficiency by packing values with binary format and
// RLE encoding. Remove the serialization from the operations and instead do it here
class CrdtTextChange {
  final List<CrdtTextOperation> operations;

  const CrdtTextChange(this.operations);

  factory CrdtTextChange.fromJson(List<dynamic> json) {
    return CrdtTextChange(
      json.map((e) => CrdtTextOperation.fromJson(e)).toList(),
    );
  }

  List<dynamic> toJson() {
    return operations.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return '[TextChange]{${operations.map((e) => e.toString()).join('\n')}';
  }
}
