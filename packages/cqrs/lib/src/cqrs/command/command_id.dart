import 'package:common/common.dart';

class CommandId extends Dot {
  CommandId(super.actorId, super.sequence);

  factory CommandId.fromJson(List<dynamic> json) {
    final dot = Dot.fromJson(json);
    return CommandId(dot.actorId, dot.sequence);
  }

  @override
  String toString() => 'CommandId(actorId: $actorId, sequence: $sequence)';

  String toStringCompact() => 'CommandId($actorId.$sequence)';
}
