import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';

abstract final class EventStoreTestUtils {
  static Future<int> getEventCount(EventStore eventStore) async =>
      (await eventStore.getLogPosition(const LogFilter.all())) + 1;

  static Future<int> getCommandCount(EventStoreReplication eventStore) async {
    final state = await eventStore.getState();
    return state.lastCommandLogPosition + 1;
  }
}
