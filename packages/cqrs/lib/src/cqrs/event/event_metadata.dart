// Other fields could be added:
// DeviceId for conflict resolution?
class EventMetadata {
  final DateTime occuredAt;
  final int localSequence;

  EventMetadata({required this.occuredAt, required this.localSequence});

  @override
  toString() =>
      'EventMetadata(occuredAt: $occuredAt, localSequence: $localSequence)';
}
