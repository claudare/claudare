import 'package:cqrs/src/cqrs/notification_bus/notification_bus.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

/// Delivers matching notifications to local listeners.
class MemoryNotificationBus implements NotificationBus {
  final List<_MemoryNotificationBusSubscription> _subscriptions = [];

  @override
  NotificationBusSubscription listen(
    PatternFilter filter,
    void Function(NotificationBusMessage) callback,
  ) {
    final subscription = _MemoryNotificationBusSubscription(
      this,
      filter,
      callback,
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  void notify(NotificationBusMessage message) {
    for (final subscription in List<_MemoryNotificationBusSubscription>.of(
      _subscriptions,
    )) {
      if (!subscription._active ||
          !subscription.filter.doesMatchPath(message.stream)) {
        continue;
      }

      try {
        subscription.callback(message);
      } on Object catch (_) {
        // A listener failure must not stop delivery to other listeners.
      }
    }
  }
}

class _MemoryNotificationBusSubscription
    implements NotificationBusSubscription {
  final MemoryNotificationBus _bus;
  final PatternFilter filter;
  final void Function(NotificationBusMessage) callback;
  bool _active = true;

  _MemoryNotificationBusSubscription(this._bus, this.filter, this.callback);

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _bus._subscriptions.remove(this);
  }
}
