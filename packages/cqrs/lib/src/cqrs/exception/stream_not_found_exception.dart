class StreamNotFoundException implements Exception {
  final String streamId;

  const StreamNotFoundException(this.streamId);

  @override
  String toString() => 'StreamNotFoundException: streamId=$streamId';
}
