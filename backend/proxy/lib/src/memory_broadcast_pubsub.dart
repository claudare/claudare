import 'package:proxy/src/pubsub.dart';

/// In-memory pub/sub allowing multiple subscriptions per group.
class MemoryBroadcastPubSub implements PubSub {
  final _listeners = <String, Map<Object, SubscribeCallback>>{};

  @override
  bool publish(String group, String data) {
    final listeners = _listeners[group];
    if (listeners == null) {
      return false;
    }

    for (final cb in listeners.values.toList()) {
      cb(data);
    }

    return true;
  }

  @override
  Unsubscribe subscribe(String group, SubscribeCallback cb) {
    final listeners = _listeners.putIfAbsent(group, () => {});
    final subscription = Object();
    listeners[subscription] = cb;

    return () {
      if (listeners.remove(subscription) == null) {
        return;
      }
      if (listeners.isEmpty) {
        _listeners.remove(group);
      }
    };
  }
}
