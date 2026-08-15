import 'package:common/common.dart';

class ReplicatedCommandConflict implements Exception {
  final Dot dot;

  const ReplicatedCommandConflict(this.dot);

  @override
  String toString() => 'different command content already exists for $dot';
}
