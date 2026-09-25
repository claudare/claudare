part of 'command_context.dart';

/// A typed handle to a stream's state within a [CommandContext].
class CommandStream<Event extends Object> {
  final CommandContext _context;
  final String _streamPath;

  CommandStream._(this._context, this._streamPath);

  /// Replays the stream and applies each event that is yielded.
  Stream<Event> scan() async* {
    _context._beginAcquisition(_streamPath);

    int? streamVersion;
    try {
      final reader = _context._eventStore.getStreamReader(_streamPath);
      await for (final event in reader.scan()) {
        final decoded = _context._eventRegistry.decode<Event>(
          event.encodedEvent,
        );
        streamVersion = event.version;
        _context._applyCommand(event.eventId.commandId);
        yield decoded;
      }
    } finally {
      // Keep the lock when a consumer stops or fails after a partial replay.
      // Its version is the last event that was successfully yielded.
      _context._endAcquisition(
        _streamPath,
        StreamLock(
          streamPath: _streamPath,
          originatingStreamVersion: streamVersion,
        ),
      );
    }
  }

  /// Replays and applies the complete stream without yielding events.
  Future<void> lockLatest() => _context._lock(_streamPath, () async {
    int? streamVersion;
    final reader = _context._eventStore.getStreamReader(_streamPath);
    await for (final event in reader.scan()) {
      streamVersion = event.version;
      _context._applyCommand(event.eventId.commandId);
    }
    return streamVersion;
  });

  /// Ensures the stream exists and applies its first event.
  Future<void> mustExist() => _context._lock(_streamPath, () async {
    final info = await _context._eventStore.getStreamInfo(_streamPath);
    if (info == null) {
      throw StreamNotFoundException(_streamPath);
    }

    final firstEvent =
        await _context._eventStore.getStreamReader(_streamPath).scan().first;
    _context._applyCommand(firstEvent.eventId.commandId);
    return info.originatingStreamVersion;
  });

  /// Requires the stream to be absent without applying any dependencies.
  Future<void> mustNotExist() => _context._lock(_streamPath, () async {
    final info = await _context._eventStore.getStreamInfo(_streamPath);
    if (info != null) {
      throw StreamAlreadyExistsException(_streamPath);
    }

    return null;
  });

  /// Appends after replay or an existence check has completed.
  CommandStream<Event> append(Event event) {
    _context._append(_streamPath, event);
    return this;
  }
}
