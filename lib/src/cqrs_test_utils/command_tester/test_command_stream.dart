import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/command/command_stream.dart';

import 'command_tester_store.dart';

class TestCommandStream<Event, IdData> implements CommandStream<Event, IdData> {
  final String _streamId;
  final EventCodec<Event> _codec;
  // final IdData _streamIdData;
  // final StreamIdPattern<IdData> _streamIdPattern;
  final CommandTesterStore _readStore;
  final CommandTesterStore _writeStore;

  bool _locked = false;

  TestCommandStream(
    this._streamId,
    this._codec,
    this._readStore,
    this._writeStore,
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
    final all = _readStore.getOnPath(_streamId);
    for (final e in all) {
      yield e.event;
    }
  }

  @override
  Future<void> lock() async {
    _tryLock();
  }

  @override
  Future<void> mustExist() async {
    _tryLock();

    final all = _readStore.getOnPath(_streamId);
    if (all.isEmpty) {
      throw StreamNotFoundException(_streamId);
    }
  }

  @override
  Future<void> mustNotExist() async {
    _tryLock();

    final all = _readStore.getOnPath(_streamId);
    if (all.isNotEmpty) {
      throw StreamAlreadyExistsException(_streamId);
    }
  }

  @override
  CommandStream<Event, IdData> append(Event event) {
    _ensureLocked();

    _writeStore.append(_streamId, _codec, event);

    return this;
  }
}
