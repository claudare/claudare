import 'package:cqrs/src/cqrs/pattern_filter.dart';

/// Exposes matching notifications as streams.
abstract interface class NotificationBusListener {
  /// Creates a single-subscription stream of matching paths, delivered
  /// asynchronously. Listening registers with the bus; cancellation unregisters.
  /// Notifications before listening are not replayed.
  Stream<String> stream(PatternFilter filter);
}

/// Sends notifications to matching listeners.
abstract interface class NotificationBusNotifier {
  void notify(String stream);
}

/// Combines notification sending and filtered listening.
abstract interface class NotificationBus
    implements NotificationBusListener, NotificationBusNotifier {}
