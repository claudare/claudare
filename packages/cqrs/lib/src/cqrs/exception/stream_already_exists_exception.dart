class StreamAlreadyExistsException implements Exception {
  final String streamPath;
  const StreamAlreadyExistsException(this.streamPath);

  @override
  String toString() =>
      'StreamAlreadyExistsException: stream "$streamPath" already exists';
}
