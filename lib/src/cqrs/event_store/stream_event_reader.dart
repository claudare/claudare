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

  int _originatingLocalVersion = 0; // careful!
  int? _localVersionCursor = 0;

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

    return value;
  }

  /// will load more. If true is returned, continue the iteration
  Future<bool> loadMore() async {
    if (_localVersionCursor == null) {
      return false;
    }
    assert(_current == null, "Iterator already exists");

    final result = await _eventStore.getStreamEventsCursor(
      _streamId,
      _pageSize,
      _localVersionCursor,
    );

    _current = result.events;
    _originatingLocalVersion = result.originatingVersion;
    _localVersionCursor = result.versionCursor;

    return true;
  }

  IterationState state() {
    return IterationState(_dependencies, _originatingLocalVersion);
  }
}

class IterationState {
  final EventDependency dependencies;
  final int originatingLocalVersion;

  IterationState(this.dependencies, this.originatingLocalVersion);
}
