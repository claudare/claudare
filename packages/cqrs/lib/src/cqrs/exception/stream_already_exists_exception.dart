class StreamAlreadyExistsException implements Exception {
  final String streamId;
  const StreamAlreadyExistsException(this.streamId);

  @override
  String toString() =>
      'StreamAlreadyExistsException: stream "$streamId" already exists';
}
