/// Identifies one command in a device's contiguous command history.
class Dot {
  final int deviceId;
  final int sequence;

  Dot(this.deviceId, this.sequence) {
    if (sequence <= 0) {
      throw FormatException('dot sequence must be positive: $sequence');
    }
  }

  List<int> toJson() => [deviceId, sequence];

  factory Dot.fromJson(List<dynamic> json) {
    if (json.length != 2) {
      throw const FormatException('dot must contain device id and sequence');
    }
    return Dot(json[0] as int, json[1] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is Dot &&
          deviceId == other.deviceId &&
          sequence == other.sequence;

  @override
  int get hashCode => Object.hash(deviceId, sequence);

  @override
  String toString() => 'Dot(deviceId: $deviceId, sequence: $sequence)';
}
