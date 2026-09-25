/// Identifies one command in an actor's contiguous command history.
class Dot {
  final int actorId;
  final int sequence;

  Dot(this.actorId, this.sequence) {
    if (sequence <= 0) {
      throw FormatException('dot sequence must be positive: $sequence');
    }
  }

  List<int> toJson() => [actorId, sequence];

  factory Dot.fromJson(List<dynamic> json) {
    if (json.length != 2) {
      throw const FormatException('dot must contain actor id and sequence');
    }
    return Dot(json[0] as int, json[1] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is Dot &&
          actorId == other.actorId &&
          sequence == other.sequence;

  @override
  int get hashCode => Object.hash(actorId, sequence);

  @override
  String toString() => 'Dot(actorId: $actorId, sequence: $sequence)';
}
