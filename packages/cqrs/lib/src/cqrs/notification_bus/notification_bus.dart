import 'package:cqrs/src/cqrs/pattern_filter.dart';

/// Cancels a single registration with a [NotificationBusListener].
abstract interface class NotificationBusSubscription {
  /// Stops future deliveries. Repeated calls have no effect.
  void cancel();
}

/// Registers callbacks for matching notifications.
abstract interface class NotificationBusListener {
  /// Creates a single-subscription stream of matching paths, delivered
  /// asynchronously. Listening registers with the bus; cancellation unregisters.
  /// Notifications before listening are not replayed.
  Stream<String> stream(PatternFilter filter);

  NotificationBusSubscription listen(
    PatternFilter filter,
    void Function(String stream) callback,
  );
}

/// Sends notifications to matching listeners.
abstract interface class NotificationBusNotifier {
  void notify(String stream);
}

/// Combines notification sending and filtered listening.
abstract interface class NotificationBus
    implements NotificationBusListener, NotificationBusNotifier {}
