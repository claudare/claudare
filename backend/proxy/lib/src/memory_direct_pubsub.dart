import 'package:proxy/src/pubsub.dart';

/// Pubsub where only one subscription is allowed
class MemoryDirectPubSub implements PubSub {
  final _listeners = <String, SubscribeCallback>{};

  @override
  bool publish(String actor, String data) {
    if (_listeners[actor] == null) {
      return false;
    }

    _listeners[actor]!(data);

    return true;
  }

  @override
  Unsubscribe subscribe(String actor, SubscribeCallback cb) {
    if (_listeners[actor] != null) {
      throw Exception('single subscription only');
    }

    _listeners[actor] = cb;

    return () {
      _listeners.remove(actor);
    };
  }
}
