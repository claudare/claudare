import 'package:core/src/cqrs/command/stored_command_write.dart';
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
    String applicationId,
    String streamId,
    int count,
    int versionCursor,
  ) {
    try {
      return _store.getStreamEvents(
        applicationId,
        streamId,
        count,
        versionCursor,
      );
    } catch (cause) {
      throw EventStoreException(
        "Failed to get stream events cursor for stream '$streamId'",
        cause: cause,
      );
    }
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfo(
    String applicationId,
    String streamId,
  ) {
    try {
      return _store.getStreamInfo(applicationId, streamId);
    } catch (cause) {
      throw EventStoreException(
        "Failed to get stream info for stream '$streamId' (last)",
        cause: cause,
      );
    }
  }

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    try {
      final result = await _store.saveChanges(command, appends);

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
    String applicationId,
    int sequenceNumber,
    PatternFilter patternFilter,
    int count,
  ) {
    try {
      return _store.getGlobalEvents(
        applicationId,
        sequenceNumber,
        patternFilter,
        count,
      );
    } catch (cause) {
      throw EventStoreException("Failed to get global events", cause: cause);
    }
  }
}
