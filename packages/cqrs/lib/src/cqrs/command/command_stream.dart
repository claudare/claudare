import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_found_exception.dart';

class CommandStream<Event extends Object> {
  final EventStore _eventStore;
  final CommandExecutionState _executionState;
  final EventRegistry _eventRegistry;
  final String _streamPath;
  final TimeProvider _timeProvider;
  final void Function(CommandId) _applyCommand;

  bool _locked = false;

  CommandStream(
    this._eventStore,
    this._executionState,
    this._eventRegistry,
    this._streamPath,
    this._timeProvider,
    this._applyCommand,
  );

  void _ensureLocked() {
    if (!_locked) {
      throw StateError('Stream not locked: $_streamPath');
    }
  }

  void _tryLock() {
    if (_locked) {
      throw StateError('Stream already locked: $_streamPath');
    }
    _locked = true;
  }

  /// Replays the stream and applies each event that is yielded.
  Stream<Event> scan() async* {
    _tryLock();

    final reader = _eventStore.getStreamReader(_streamPath);
    var streamVersion = 0;

    try {
      await for (final event in reader.scan()) {
        final decoded = _eventRegistry.decode<Event>(event.encodedEvent);
        streamVersion = event.streamVersion;
        _applyCommand(event.commandId);
        yield decoded;
      }
    } finally {
      // Keep the lock when a consumer stops or fails after a partial replay.
      // Its version is the last event that was successfully yielded.
      _executionState.locks.add(
        StreamLocalLock(
          streamPath: _streamPath,
          originatingStreamVersion: streamVersion,
        ),
      );
    }
  }

  /// Replays and applies the complete stream without yielding events.
  Future<void> lockLatest() async {
    _tryLock();

    var streamVersion = 0;
    final reader = _eventStore.getStreamReader(_streamPath);
    await for (final event in reader.scan()) {
      streamVersion = event.streamVersion;
      _applyCommand(event.commandId);
    }

    _executionState.locks.add(
      StreamLocalLock(
        streamPath: _streamPath,
        originatingStreamVersion: streamVersion,
      ),
    );
  }

  /// Ensures the stream exists and applies its first event.
  Future<void> mustExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamPath);
    if (info == null) {
      throw StreamNotFoundException(_streamPath);
    }

    final firstEvent =
        await _eventStore.getStreamReader(_streamPath).scan().first;
    _applyCommand(firstEvent.commandId);

    _executionState.locks.add(
      StreamLocalLock(
        streamPath: _streamPath,
        originatingStreamVersion: info.originatingStreamVersion,
      ),
    );
  }

  /// Requires the stream to be absent without applying any dependencies.
  Future<void> mustNotExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamPath);
    if (info != null) {
      throw StreamAlreadyExistsException(_streamPath);
    }

    _executionState.locks.add(
      StreamLocalLock(streamPath: _streamPath, originatingStreamVersion: 0),
    );
  }

  CommandStream<Event> append(Event event) {
    _ensureLocked();

    final occuredAt = _timeProvider.now();

    final encodedEvent = _eventRegistry.encode(event);

    _executionState.events.add(
      EventAppend(
        streamPath: _streamPath,
        encodedEvent: encodedEvent,
        occuredAt: occuredAt,
      ),
    );

    return this;
  }
}
