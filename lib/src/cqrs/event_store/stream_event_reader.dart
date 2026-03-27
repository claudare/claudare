import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';

class StreamEventReader {
  final EventStoreCommand _eventStore;
  final int _pageSize;
  final String _streamId;

  Iterator<StoredEventCommandRead>? _current;

  final EventDependency _dependencies = EventDependency.empty();

  bool done = false;
  int _originatingLocalVersion = -1; // careful!
  int _localVersionCursor = 0;

  StreamEventReader(this._eventStore, this._pageSize, this._streamId);

  StoredEventCommandRead? next() {
    assert(_current != null, "No iterator available");

    if (!_current!.moveNext()) {
      return null;
    }

    final value = _current!.current;

    _dependencies.add(
      DeviceIdSequencePair(value.deviceId, value.causalSequence),
    );
    _localVersionCursor = value.localVersion;

    return value;
  }

  /// will load more. If true is returned, continue the iteration
  Future<bool> loadMore() async {
    if (_localVersionCursor == _originatingLocalVersion) {
      return false;
    }

    final result = await _eventStore.getStreamEvents(
      _streamId,
      _pageSize,
      _localVersionCursor,
    );

    _current = result.events.iterator;
    _originatingLocalVersion = result.originatingVersion;

    return true;
  }

  IterationState state() {
    return IterationState(_dependencies, _originatingLocalVersion);
  }

  /// do not use this. Its only for tests
  Stream<StoredEventCommandRead> scanStored() async* {
    while (await loadMore()) {
      StoredEventCommandRead? e;
      while ((e = next()) != null) {
        yield e!;
      }
    }
  }
}

class IterationState {
  final EventDependency dependencies;
  final int originatingLocalVersion;

  IterationState(this.dependencies, this.originatingLocalVersion);
}
