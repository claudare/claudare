import 'package:common/common.dart';

class CommandId extends Dot {
  CommandId(super.deviceId, super.sequence);

  factory CommandId.fromJson(List<dynamic> json) {
    final dot = Dot.fromJson(json);
    return CommandId(dot.deviceId, dot.sequence);
  }

  @override
  String toString() => 'CommandId(deviceId: $deviceId, sequence: $sequence)';
}
