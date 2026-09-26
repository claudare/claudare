part of 'crdt_text.dart';

/// A Lamport counter and the identity of its single writer.
final class CrdtTextId implements Comparable<CrdtTextId> {
  final String actorId;
  final int counter;

  CrdtTextId({required this.actorId, required this.counter}) {
    _requireActor(actorId);
    _requireCounter(counter);
  }

  factory CrdtTextId.fromJson(Object? json) {
    final map = json as Map<String, dynamic>;
    return CrdtTextId(
      actorId: map['actorId'] as String,
      counter: map['counter'] as int,
    );
  }

  Map<String, Object?> toJson() => {'actorId': actorId, 'counter': counter};

  @override
  int compareTo(CrdtTextId other) {
    final counters = counter.compareTo(other.counter);
    return counters == 0 ? actorId.compareTo(other.actorId) : counters;
  }

  @override
  bool operator ==(Object other) =>
      other is CrdtTextId &&
      actorId == other.actorId &&
      counter == other.counter;

  @override
  int get hashCode => Object.hash(actorId, counter);
}
