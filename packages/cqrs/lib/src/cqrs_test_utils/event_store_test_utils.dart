import 'package:cqrs/src/cqrs/event_store/event_store.dart';

abstract final class EventStoreTestUtils {
  static Future<int> getEventCount(EventStoreReplication eventStore) async {
    final state = await eventStore.getState();
    final position = state.lastEventLogPosition;

    return position == null ? 0 : position + 1;
  }

  static Future<int> getCommandCount(EventStoreReplication eventStore) async {
    final state = await eventStore.getState();
    final position = state.lastCommandLogPosition;

    return position == null ? 0 : position + 1;
  }
}
