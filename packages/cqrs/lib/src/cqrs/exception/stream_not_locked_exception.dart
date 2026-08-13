class StreamNotLockedException implements Exception {
  final String streamId;

  const StreamNotLockedException(this.streamId);

  @override
  String toString() => 'StreamNotLockedException: $streamId is not locked';
}
