class StreamAlreadyLockedException implements Exception {
  final String streamId;

  StreamAlreadyLockedException(this.streamId);

  @override
  String toString() =>
      'StreamAlreadyLockedException: $streamId is already locked';
}
