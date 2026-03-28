import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

// TODO: refactor to use lists as well
class GlobalEventReader {
  final EventStoreProjection _underlying;
  final int _pageSize;
  final PatternFilter _patternFilter;

  Iterator<StoredEventProjectionRead>? _current;

  int? _localSequenceCursor = 0;

  GlobalEventReader(this._underlying, this._pageSize, this._patternFilter);

  StoredEventProjectionRead? next() {
    assert(_current != null, "No iterator available");

    if (!_current!.moveNext()) {
      return null;
    }

    final value = _current!.current;

    return value;
  }

  /// will load more. If true is returned, continue the iteration
  Future<bool> loadMore() async {
    if (_localSequenceCursor == null) {
      return false;
    }
    assert(_current == null, "Iterator already exists");

    final result = await _underlying.getGlobalEvents(_localSequenceCursor!, [
      _patternFilter,
    ], _pageSize);

    _current = result.events.iterator;
    _localSequenceCursor = result.sequenceNumberCursor;

    return true;
  }
}

class IterationState {
  final EventDependency dependencies;
  final int originatingLocalVersion;

  IterationState(this.dependencies, this.originatingLocalVersion);
}
