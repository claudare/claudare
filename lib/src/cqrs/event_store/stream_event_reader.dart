import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';

class StreamEventReader {
  final EventStoreCommand _eventStore;
  final int _pageSize;
  final String _streamId;

  List<StoredEventCommandRead> _current = const [];
  int _originatingLocalVersion = -1;

  StreamEventReader(this._eventStore, this._pageSize, this._streamId);

  List<StoredEventCommandRead> get currentPage => _current;

  Future<bool> loadMore() async {
    if (_current.isNotEmpty &&
        _current.last.localVersion == _originatingLocalVersion) {
      return false;
    }

    final cursor = _current.isEmpty ? 0 : _current.last.localVersion;
    final result = await _eventStore.getStreamEvents(
      _streamId,
      _pageSize,
      cursor,
    );

    _current = result.events;
    _originatingLocalVersion = result.originatingVersion;

    return _current.isNotEmpty;
  }

  StreamLock get streamLock => StreamLock(
    streamId: _streamId,
    originatingVersion: _originatingLocalVersion,
  );
}
