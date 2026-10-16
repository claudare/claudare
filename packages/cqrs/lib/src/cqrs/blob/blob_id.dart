/// Identifies a blob by its actor and sequence.
class BlobId {
  final String actor;
  final int sequence;
  const BlobId(this.actor, this.sequence);

  List<dynamic> toJson() => [actor, sequence];

  factory BlobId.fromJson(List<dynamic> json) {
    if (json.length != 2) {
      throw const FormatException('command id must contain actor and sequence');
    }
    return BlobId(json[0] as String, json[1] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is BlobId &&
          actor == other.actor &&
          sequence == other.sequence;

  @override
  int get hashCode => Object.hash(actor, sequence);

  @override
  String toString() => 'BlobId($actor,$sequence)';
}
