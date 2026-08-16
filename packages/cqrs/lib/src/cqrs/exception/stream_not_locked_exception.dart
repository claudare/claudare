class StreamNotLockedException implements Exception {
  final String streamPath;

  const StreamNotLockedException(this.streamPath);

  @override
  String toString() => 'StreamNotLockedException: $streamPath is not locked';
}
