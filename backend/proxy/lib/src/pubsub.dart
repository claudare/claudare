/// A simple pub-sub system.
/// The server does not tell who messages or coming from. The application will
/// check it via encryption and signatures.
/// The server is simply passing payloads it would not be able to read.
abstract interface class PubSub {
  /// Subscribe for an actor. Returns null when subscription already exists.
  Unsubscribe? subscribe(String actor, SubscribeCallback cb);

  /// True on success, false on failure
  bool publish(String actor, String data);
}

typedef Unsubscribe = void Function();
typedef SubscribeCallback = void Function(String test);

class MemoryPubSub implements PubSub {
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
  Unsubscribe? subscribe(String actor, SubscribeCallback cb) {
    if (_listeners[actor] != null) {
      return null;
    }

    _listeners[actor] = cb;

    return () {
      _listeners.remove(actor);
    };
  }
}
