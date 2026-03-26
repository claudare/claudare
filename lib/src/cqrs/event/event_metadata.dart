class EventMetadata {
  final DateTime occuredAt;
  final int localSequence;
  final int localVersion;

  EventMetadata({
    required this.occuredAt,
    required this.localSequence,
    required this.localVersion,
  });
}
