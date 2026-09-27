import 'dart:async';

import 'package:cqrs/src/cqrs/notification_bus/notification_bus.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

/// Delivers matching notifications to local listeners.
class MemoryNotificationBus implements NotificationBus {
  final Map<StreamController<String>, PatternFilter> _subscriptions = {};

  @override
  Stream<String> stream(PatternFilter filter) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () => _subscriptions[controller] = filter,
      onCancel: () => _subscriptions.remove(controller),
    );
    return controller.stream;
  }

  @override
  void notify(String stream) {
    for (final entry in _subscriptions.entries.toList()) {
      if (_subscriptions.containsKey(entry.key) &&
          entry.value.doesMatchPath(stream)) {
        entry.key.add(stream);
      }
    }
  }
}
