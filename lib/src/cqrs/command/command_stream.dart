abstract interface class CommandStream<Event, IdData> {
  /// Returns an asynchronous dart abstract mixin class [Stream] for the events
  /// Only the latest seen event will be used in the dependencies
  Stream<Event> scan();

  /// The stream could exist or could not exist.
  /// Locks the stream to the latest version.
  Future<void> lock();

  /// Ensure stream exists.
  /// Locks to the latest version.
  Future<void> mustExist();

  // TODO: idea: allow optionally nacking an error when stream does not exist
  // this will provide better error handling
  // Future<void> mustExistNackIdea({Object nackFailure});

  /// Ensures the stream does not exist.
  /// Locks to the zero version.
  Future<void> mustNotExist();

  /// Appends event to this stream.
  /// The stream must be locked, or else it will throw.
  CommandStream<Event, IdData> append(Event event);
}
