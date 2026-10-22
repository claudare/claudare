import 'package:proxy/src/pubsub.dart';

/// Pubsub where only one subscription is allowed
class MemoryDirectPubSub implements PubSub {
  final _listeners = <String, SubscribeCallback>{};

  @override
  bool publish(String target, String data) {
    if (_listeners[target] == null) {
      return false;
    }

    _listeners[target]!(data);

    return true;
  }

  @override
  Unsubscribe subscribe(String target, SubscribeCallback cb) {
    if (_listeners[target] != null) {
      throw Exception('single subscription only');
    }

    _listeners[target] = cb;

    return () {
      _listeners.remove(target);
    };
  }
}
