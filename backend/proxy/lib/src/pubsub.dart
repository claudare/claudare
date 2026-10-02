/// A simple pub-sub system.
/// The server does not tell who messages or coming from. The application will
/// check it via encryption and signatures.
/// The server is simply passing payloads it would not be able to read.
abstract interface class PubSub {
  /// Subscribe for an actor. Returns null when subscription already exists.
  Unsubscribe subscribe(String topic, SubscribeCallback cb);

  /// True on success, false on failure
  bool publish(String topic, String data);
}

typedef Unsubscribe = void Function();
typedef SubscribeCallback = void Function(String test);
