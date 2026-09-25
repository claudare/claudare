import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

class EventDatabaseState {
  final int? lastCommandLogPosition;
  final int? lastEventLogPosition;
  final VersionVector logVersion;

  const EventDatabaseState({
    required this.lastCommandLogPosition,
    required this.lastEventLogPosition,
    required this.logVersion,
  });
}

abstract interface class EventDatabase {
  int get defaultEventFetchPageSize;

  // general state
  Future<GetStatisticsResult> getStatistics();
  Future<EventDatabaseState> getState();

  // reading
  Future<int?> getStreamVersion(String streamPath);
  Future<PaginatedResult<LogEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
    int count,
  );
  Future<PaginatedResult<LogEvent>> getLogEvents(int fromPosition, int count);

  /// Saves a complete bundle when its dependencies and command ID are ready.
  /// Returns false when the bundle is out of order.
  Future<bool> saveBundle(CommandBundle bundle);

  /// Returns a logged bundle by command ID, or null when absent.
  Future<CommandBundle?> getBundle(CommandId commandId);
}
