/// Identifies a command by its actor and sequence.
class CommandId {
  final String actor;
  final int sequence;
  const CommandId(this.actor, this.sequence);

  List<dynamic> toJson() => [actor, sequence];

  factory CommandId.fromJson(List<dynamic> json) {
    if (json.length != 2) {
      throw const FormatException('command id must contain actor and sequence');
    }
    return CommandId(json[0] as String, json[1] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is CommandId &&
          actor == other.actor &&
          sequence == other.sequence;

  @override
  int get hashCode => Object.hash(actor, sequence);

  @override
  String toString() => 'CommandId($actor,$sequence)';
}
