class StreamDeletedException implements Exception {
  final String streamPath;

  const StreamDeletedException(this.streamPath);

  @override
  String toString() => 'StreamDeletedException: streamPath=$streamPath';
}
