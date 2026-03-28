import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/exception/event_store_exception.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

// TODO: separate to projection vs commnd
// TODO: rename to Adapter
class EventStoreSafe implements EventStore {
  final EventStore _store;

  const EventStoreSafe(this._store); //: assert(_store )

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int count,
    int versionCursor,
  ) {
    try {
      return _store.getStreamEvents(streamId, count, versionCursor);
    } catch (cause) {
      throw EventStoreException(
        "Failed to get stream events cursor for stream '$streamId'",
        cause: cause,
      );
    }
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfoLast(String streamId) {
    try {
      return _store.getStreamInfoLast(streamId);
    } catch (cause) {
      throw EventStoreException(
        "Failed to get stream info for stream '$streamId' (last)",
        cause: cause,
      );
    }
  }

  @override
  Future<StreamAppendResult> multiAppendEvents(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    try {
      final result = await _store.multiAppendEvents(command, appends);

      assert(result.orders.length == appends.events.length);

      return result;
    } on ConcurrencyProblem {
      throw ConcurrencyProblem();
    } catch (cause) {
      throw EventStoreException("Failed to multi append events", cause: cause);
    }
  }

  @override
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  ) {
    try {
      return _store.getGlobalEvents(sequenceNumber, aggregateFilters, count);
    } catch (cause) {
      throw EventStoreException("Failed to get global events", cause: cause);
    }
  }
}
