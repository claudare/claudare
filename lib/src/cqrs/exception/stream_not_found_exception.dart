class StreamNotFoundException implements Exception {
  final String streamId;

  StreamNotFoundException(this.streamId);

  @override
  String toString() => 'StreamNotFoundException: streamId=$streamId';
}
