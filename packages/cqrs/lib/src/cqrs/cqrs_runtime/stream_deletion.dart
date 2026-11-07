/// Metadata for a permanent stream deletion.
class StreamDeletion {
  final String actor;
  final String streamPath;
  final DateTime occuredAt;

  const StreamDeletion({
    required this.actor,
    required this.streamPath,
    required this.occuredAt,
  });
}
