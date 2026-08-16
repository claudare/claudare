import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_locked_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_found_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_locked_exception.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

import 'command_stream.dart';

class CommandStreamImpl<Event, IdData> implements CommandStream<Event, IdData> {
  final EventStore _eventStore;
  final CommandExecutionState _executionState;
  final EventCodec<Event> _codec;
  final String _streamId;
  final IdData _streamIdData;
  final StreamIdPattern<IdData> _streamIdPattern;
  final TimeProvider _timeProvider;

  bool _locked = false;

  CommandStreamImpl(
    this._eventStore,
    this._executionState,
    this._codec,
    this._streamId,
    this._streamIdData,
    this._streamIdPattern,
    this._timeProvider,
  );

  void _ensureLocked() {
    if (!_locked) {
      throw StreamNotLockedException(_streamId);
    }
  }

  void _tryLock() {
    if (_locked) {
      throw StreamAlreadyLockedException(_streamId);
    }
    _locked = true;
  }

  @override
  Stream<Event> scan() async* {
    _tryLock();

    final reader = _eventStore.getStreamReader(_streamId);
    var streamVersion = 0;

    try {
      await for (final event in reader.scan()) {
        streamVersion = event.streamVersion;
        yield _codec.decode(event.encodedEvent);
      }
    } finally {
      // TODO: explain why this is in the finally block
      // instead of after the try block
      _executionState.locks.add(
        StreamLocalLock(
          streamId: _streamId,
          originatingStreamVersion: streamVersion,
        ),
      );
    }
  }

  @override
  Future<void> lock() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamId);

    if (info == null) {
      _executionState.locks.add(
        StreamLocalLock(streamId: _streamId, originatingStreamVersion: 0),
      );
      return;
    }

    _executionState.locks.add(
      StreamLocalLock(
        streamId: _streamId,
        originatingStreamVersion: info.originatingStreamVersion,
      ),
    );

    return;
  }

  @override
  Future<void> mustExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamId);
    if (info == null) {
      throw StreamNotFoundException(_streamId);
    }

    _executionState.locks.add(
      StreamLocalLock(
        streamId: _streamId,
        originatingStreamVersion: info.originatingStreamVersion,
      ),
    );
  }

  @override
  Future<void> mustNotExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfo(_streamId);
    if (info != null) {
      throw StreamAlreadyExistsException(_streamId);
    }

    _executionState.locks.add(
      StreamLocalLock(streamId: _streamId, originatingStreamVersion: 0),
    );
  }

  @override
  CommandStream<Event, IdData> append(Event event) {
    _ensureLocked();

    final occuredAt = _timeProvider.now();

    final encodedEvent = _codec.encode(event);

    _executionState.events.add(
      CommandExecutionEvent<Event, IdData>(
        streamIdStr: _streamId,
        streamIdData: _streamIdData,
        streamIdPattern: _streamIdPattern,
        runtimeEvent: event,
        encodedEvent: encodedEvent,
        occuredAt: occuredAt,
      ),
    );

    return this;
  }

  // CommandStream<Event, IdData> appendMany(Iterable<Event> events) {
  //   _ensureLocked();

  //   for (var event in events) {
  //     append(event);
  //   }
  //   return this;
  // }
}
