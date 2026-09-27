import 'package:cqrs/src/cqrs/pattern_filter.dart';

/// Identifies a stream update available in the global log.
class NotificationBusMessage {
  final String stream;
  final int position;
  final int version;

  const NotificationBusMessage({
    required this.stream,
    required this.position,
    required this.version,
  });
}

/// Cancels a single registration with a [NotificationBusListener].
abstract interface class NotificationBusSubscription {
  /// Stops future deliveries. Repeated calls have no effect.
  void cancel();
}

/// Registers callbacks for matching notifications.
abstract interface class NotificationBusListener {
  NotificationBusSubscription listen(
    PatternFilter filter,
    void Function(NotificationBusMessage) callback,
  );
}

/// Sends notifications to matching listeners.
abstract interface class NotificationBusNotifier {
  void notify(NotificationBusMessage message);
}

/// Combines notification sending and filtered listening.
abstract interface class NotificationBus
    implements NotificationBusListener, NotificationBusNotifier {}
