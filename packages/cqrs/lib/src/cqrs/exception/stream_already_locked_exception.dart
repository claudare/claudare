class StreamAlreadyLockedException implements Exception {
  final String streamPath;

  const StreamAlreadyLockedException(this.streamPath);

  @override
  String toString() =>
      'StreamAlreadyLockedException: $streamPath is already locked';
}
