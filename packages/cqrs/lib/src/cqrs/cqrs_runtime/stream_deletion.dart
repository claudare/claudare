/// Metadata for a permanent stream deletion.
class StreamDeletion {
  final String actor;
  final String streamPath;
  final DateTime occuredAt;
  final int logPosition;

  const StreamDeletion({
    required this.actor,
    required this.streamPath,
    required this.occuredAt,
    required this.logPosition,
  });
}
