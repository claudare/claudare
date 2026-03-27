import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/stream_event_reader.dart';
import 'package:core/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:core/src/cqrs/exception/stream_already_locked_exception.dart';
import 'package:core/src/cqrs/exception/stream_not_found_exception.dart';
import 'package:core/src/cqrs/exception/stream_not_locked_exception.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandStream<Event, IdData> {
  final EventStoreCommand _eventStore;
  final CommandAppends _appends;
  final EventCodec<Event> _codec;
  final int _pageSize; // TODO: unhardcode
  final String _streamId;
  final IdData _streamIdData;
  final StreamIdPattern<IdData> _streamIdPattern;

  bool _locked = false;

  CommandStream(
    this._eventStore,
    this._appends,
    this._codec,
    this._pageSize,
    this._streamId,
    this._streamIdData,
    this._streamIdPattern,
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
  Stream<Event> scan() async* {
    _tryLock();

    final reader = StreamEventReader(_eventStore, _pageSize, _streamId);

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

  Stream<Event> scan2() async* {
    final reader = StreamEventReader(_eventStore, _pageSize, _streamId);

    final scanStored = reader.scanStored();

    try {
      await for (final e in scanStored) {
        yield _codec.decode(EncodedEvent(kind: e.kind, detail: e.detail));
      }
    } finally {
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

  /// Just performs the simplest lock. Stream could exist or could not exist.
  /// This will try to lock dependencies to the **last** event in the stream.
  /// TODO: this needs more considerations from naming/usability perspective
  /// maybe rename to `lockAny`?
  Future<void> lock() async {
    _tryLock();

    final info = await _eventStore.getStreamInfoLast(_streamId);

    if (info == null) {
      _appends.locks.add(
        StreamLock(streamId: _streamId, originatingVersion: 0),
      );
      return;
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

  CommandStream<Event, IdData> append(Event event) {
    _ensureLocked();

    final occuredAt = DateTime.now(); // TODO: side effect!

    // todo: this should encode here, but also pass the raw event
    // this is done so that encoding errors are readable and apparent
    // the failures are at the call site
    // do not encode here!
    final encodedEvent = _codec.encode(event);

    _appends.appendEvents.add(
      CommandAppendEvent<Event, IdData>(
        streamIdStr: _streamId,
        streamIdData: _streamIdData,
        streamIdPattern: _streamIdPattern,
        event: event,
        encodedEvent: encodedEvent,
        occuredAt: occuredAt,
      ),
    );

    return this;
  }

  CommandStream<Event, IdData> appendMany(Iterable<Event> events) {
    _ensureLocked();

    for (var event in events) {
      append(event);
    }
    return this;
  }
}
