import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_administration.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

class EventStoreSafe implements EventStore {
  final EventStore _store;

  const EventStoreSafe(this._store); //: assert(_store )

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int versionCursor,
  ) async {
    try {
      return await _store.getStreamEvents(streamId, versionCursor);
    } catch (cause) {
      throw EventStoreException(
        "Failed to get stream events cursor for stream '$streamId'",
        cause: cause,
      );
    }
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfo(String streamId) async {
    try {
      return await _store.getStreamInfo(streamId);
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
    assert(appends.isValid(), 'appends are not valid');

    try {
      final result = await _store.saveChanges(command, appends);

      assert(result.orders.length == appends.events.length);

      return result;
    } on ConcurrencyProblem {
      throw ConcurrencyProblem();
    } catch (cause) {
      throw EventStoreException('Failed to multi append events', cause: cause);
    }
  }

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
  ) async {
    try {
      return await _store.getLocalEvents(patternFilter, sequenceNumber);
    } catch (cause) {
      throw EventStoreException('Failed to get global events', cause: cause);
    }
  }

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) async {
    try {
      return await _store.getLocalLastEvent(patternFilter);
    } catch (cause) {
      throw EventStoreException(
        'Failed to get global last event',
        cause: cause,
      );
    }
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    try {
      return await _store.getStatistics();
    } catch (cause) {
      throw EventStoreException('Failed to get statistics', cause: cause);
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _store.reset();
    } catch (cause) {
      throw EventStoreException('Failed to reset', cause: cause);
    }
  }
}
