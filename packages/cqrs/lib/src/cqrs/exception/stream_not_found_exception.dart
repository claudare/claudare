class StreamNotFoundException implements Exception {
  final String streamPath;

  const StreamNotFoundException(this.streamPath);

  @override
  String toString() => 'StreamNotFoundException: streamPath=$streamPath';
}
