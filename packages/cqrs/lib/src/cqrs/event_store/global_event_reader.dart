import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

// TODO: refactor to use lists as well
class GlobalEventReader {
  final EventStoreProjection _underlying;
  final PatternFilter _patternFilter;

  Iterator<StoredEventProjectionRead>? _current;

  int? _localSequenceCursor;

  GlobalEventReader(
    this._underlying,
    this._patternFilter,
    int localSequenceCursor,
  ) {
    _localSequenceCursor = localSequenceCursor;
  }

  StoredEventProjectionRead? next() {
    assert(_current != null, 'No iterator available');

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

    final result = await _underlying.getLocalEvents(
      _patternFilter,
      _localSequenceCursor!,
    );

    _current = result.events.iterator;
    _localSequenceCursor = result.sequenceNumberCursor;

    return true;
  }
}
