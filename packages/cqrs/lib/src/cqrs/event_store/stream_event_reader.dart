import 'package:cqrs/src/cqrs/event/stored_event_command_read.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';

class StreamEventReader {
  final EventStoreCommand _eventStore;
  final String _streamId;

  List<StoredEventCommandRead> _current = const [];
  int _originatingStreamVersion = -1;

  StreamEventReader(this._eventStore, this._streamId);

  List<StoredEventCommandRead> get currentPage => _current;

  Future<bool> loadMore() async {
    if (_current.isNotEmpty &&
        _current.last.streamVersion == _originatingStreamVersion) {
      return false;
    }

    final cursor = _current.isEmpty ? 0 : _current.last.streamVersion;
    final result = await _eventStore.getStreamEvents(_streamId, cursor);

    _current = result.events;
    _originatingStreamVersion = result.originatingStreamVersion;

    return _current.isNotEmpty;
  }

  StreamLocalLock get streamLock => StreamLocalLock(
    streamId: _streamId,
    originatingStreamVersion: _originatingStreamVersion,
  );
}
