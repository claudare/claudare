import 'package:common/common.dart';

class StagedCommandConflict implements Exception {
  final Dot dot;

  const StagedCommandConflict(this.dot);

  @override
  String toString() => 'different command content already exists for $dot';
}
