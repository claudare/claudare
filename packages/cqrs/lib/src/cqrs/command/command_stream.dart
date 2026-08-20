import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_locked_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_found_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_locked_exception.dart';

class CommandStream<Event extends Object> {
  final EventStore _eventStore;
  final CommandExecutionState _executionState;
  final EventRegistry _eventRegistry;
  final String _streamPath;
  final TimeProvider _timeProvider;

  bool _locked = false;

  CommandStream(
    this._eventStore,
    this._executionState,
    this._eventRegistry,
    this._streamPath,
    this._timeProvider,
  );

  void _ensureLocked() {
    if (!_locked) {
      throw StreamNotLockedException(_streamPath);
    }
  }

  void _tryLock() {
    if (_locked) {
      throw StreamAlreadyLockedException(_streamPath);
    }
    _locked = true;
  }

  Stream<Event> scan() async* {
    _tryLock();

    final reader = _eventStore.getStreamReader(_streamPath);
    var streamVersion = 0;

    try {
      await for (final event in reader.scan()) {
        streamVersion = event.streamVersion;
        yield _eventRegistry.decode<Event>(event.encodedEvent);
      }
    } finally {
      // TODO: explain why this is in the finally block
      // instead of after the try block
      _executionState.locks.add(
        StreamLocalLock(
          streamPath: _streamPath,
          originatingStreamVersion: streamVersion,
        ),
      );
    }
  }

  Future<void> lock() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamPath);

    if (info == null) {
      _executionState.locks.add(
        StreamLocalLock(streamPath: _streamPath, originatingStreamVersion: 0),
      );
      return;
    }

    _executionState.locks.add(
      StreamLocalLock(
        streamPath: _streamPath,
        originatingStreamVersion: info.originatingStreamVersion,
      ),
    );

    return;
  }

  Future<void> mustExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamPath);
    if (info == null) {
      throw StreamNotFoundException(_streamPath);
    }

    _executionState.locks.add(
      StreamLocalLock(
        streamPath: _streamPath,
        originatingStreamVersion: info.originatingStreamVersion,
      ),
    );
  }

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
