part of 'command_context.dart';

/// A typed handle to a stream accessed through [CommandContextApi].
class CommandStream<Event extends Object> {
  final CommandContext _context;
  final String _streamPath;

  CommandStream._(this._context, this._streamPath);

  /// Replays the stream and applies each event that is yielded.
  Stream<Event> scan() async* {
    _context._beginAcquisition(_streamPath);

    var streamVersion = -1;
    try {
      final info = await _context._eventStore.getStreamInfo(_streamPath);
      if (info.isDeleted) throw StreamDeletedException(_streamPath);
      await for (final event in _context._streamReader(_streamPath)) {
        if (event.encodedEvent.isEventErased ||
            event.encodedEvent.isStreamDeleted) {
          _context._applyCommand(event.eventId.commandId);
          streamVersion = event.version;
          continue;
        }
        final decoded = _context._eventRegistry.decode<Event>(
          event.encodedEvent,
        );
        _context._applyCommand(event.eventId.commandId);
        streamVersion = event.version;
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
    final info = await _context._eventStore.getStreamInfo(_streamPath);
    if (info.isDeleted) throw StreamDeletedException(_streamPath);
    var streamVersion = -1;
    await for (final event in _context._streamReader(_streamPath)) {
      streamVersion = event.version;
      _context._applyCommand(event.eventId.commandId);
    }
    return streamVersion;
  });

  /// Ensures the stream exists and locks on to its first event.
  Future<void> mustExist() => _context._lock(_streamPath, () async {
    final info = await _context._eventStore.getStreamInfo(_streamPath);
    if (!info.streamExists()) {
      throw StreamNotFoundException(_streamPath);
    }
    if (info.isDeleted) throw StreamDeletedException(_streamPath);
    final firstEvent = await _context._streamReader(_streamPath).first;
    _context._applyCommand(firstEvent.eventId.commandId);
    return info.version;
  });

  /// Requires the stream to be absent without applying any dependencies.
  Future<void> mustNotExist() => _context._lock(_streamPath, () async {
    final info = await _context._eventStore.getStreamInfo(_streamPath);
    if (info.isDeleted) throw StreamDeletedException(_streamPath);
    if (info.streamExists()) {
      throw StreamAlreadyExistsException(_streamPath);
    }

    return -1;
  });

  /// Appends after replay or an existence check has completed.
  CommandStream<Event> append(Event event) {
    _context._append(_streamPath, event);
    return this;
  }

  /// Permanently deletes the stream after locking it to its first event.
  /// Do not lock manually.
  Future<void> delete() async {
    await mustExist();
    _context._delete(_streamPath);
  }
}
