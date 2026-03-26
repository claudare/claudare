import 'package:core/src/cqrs/command/event_store_stream_reader.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:core/src/cqrs/exception/stream_already_locked_exception.dart';
import 'package:core/src/cqrs/exception/stream_not_found_exception.dart';
import 'package:core/src/cqrs/exception/stream_not_locked_exception.dart';

class CommandStream<Event> {
  final EventStoreCommand _eventStore;
  final StreamAppends _appends;
  final EventCodec<Event> _codec;
  final int _pageSize; // TODO: unhardcode
  final String _streamId;
  bool _locked = false;

  CommandStream(
    this._eventStore,
    this._appends,
    this._codec,
    this._pageSize,
    this._streamId,
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

  /// Returns an asynchronous dart abstract mixin class [Stream] for the events
  /// Only the latest seen event will be used in the dependencies
  Stream<Event> iterator() async* {
    _tryLock();

    final reader = EventStoreStreamReader(_eventStore, _pageSize, _streamId);

    try {
      while (await reader.loadMore()) {
        StoredEventCommandRead? e;
        while ((e = reader.next()) != null) {
          yield _codec.decode(EncodedEvent(kind: e!.kind, detail: e.detail));
        }
      }
    } finally {
      // always lock on regardless of if the stream was read fully.
      // this is an intended behavior

      final state = reader.state();
      _appends.dependencies.merge(state.dependencies);
      _appends.locks.add(
        StreamLock(
          streamId: _streamId,
          originatingVersion: state.originatingLocalVersion,
        ),
      );
    }
  }

  /// Ensures the stream exists.
  /// This will lock dependencies to the **last** event in the stream.
  Future<void> lockLatest() async {
    _tryLock();

    final info = await _eventStore.getStreamInfoLast(_streamId);

    if (info == null) {
      throw StreamNotFoundException(_streamId);
    }

    _appends.dependencies.add(info.causalSequencePair);
    _appends.locks.add(
      StreamLock(
        streamId: _streamId,
        originatingVersion: info.originatingVersion,
      ),
    );

    return;
  }

  /// Ensures the stream does not exist.
  /// No dependencies are defined
  Future<void> mustNotExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfoFirst(_streamId);
    if (info != null) {
      throw StreamAlreadyExistsException(_streamId);
    }

    _appends.locks.add(StreamLock(streamId: _streamId, originatingVersion: 0));
  }

  /// Ensure stream exists.
  /// This will lock dependencies to the **first** event in the stream.
  /// Use this sparingly. Prefer to call [lockLatest] instead.
  Future<void> mustExist() async {
    _tryLock();

    final info = await _eventStore.getStreamInfoFirst(_streamId);
    if (info == null) {
      throw StreamNotFoundException(_streamId);
    }

    _appends.dependencies.add(info.causalSequencePair);
    _appends.locks.add(
      StreamLock(
        streamId: _streamId,
        originatingVersion: info.originatingVersion,
      ),
    );
  }

  CommandStream<Event> append(Event event) {
    _ensureLocked();

    final encoded = _codec.encode(event);
    _appends.events.add(
      StoredEventCommandWrite(
        streamId: _streamId,
        kind: encoded.kind,
        detail: encoded.detail,
        occuredAt: DateTime.now(), // TODO: side effect!
      ),
    );

    return this;
  }

  CommandStream<Event> appendMany(Iterable<Event> events) {
    _ensureLocked();

    for (var event in events) {
      append(event);
    }
    return this;
  }
}
