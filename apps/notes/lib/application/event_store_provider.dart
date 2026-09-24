import 'package:cqrs/cqrs.dart';
import 'package:flutter/widgets.dart';

/// Gives Settings access to event statistics and the root reset action.
class EventStoreProvider extends InheritedWidget {
  final EventStore eventStore;
  final Future<void> Function() reset;

  const EventStoreProvider({
    super.key,
    required super.child,
    required this.eventStore,
    required this.reset,
  });

  static EventStoreProvider of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EventStoreProvider>()!;

  @override
  bool updateShouldNotify(EventStoreProvider oldWidget) =>
      eventStore != oldWidget.eventStore || reset != oldWidget.reset;
}
