import 'package:flutter/widgets.dart';
import 'package:sync/sync.dart';

/// Provides the current sync runtime.
class NoteSyncProvider extends InheritedWidget {
  final SyncCoordinator? coordinator;
  final String unavailableReason;

  const NoteSyncProvider({
    super.key,
    required super.child,
    this.coordinator,
    this.unavailableReason = 'Disabled',
  });

  static NoteSyncProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteSyncProvider>();

  @override
  bool updateShouldNotify(NoteSyncProvider oldWidget) =>
      coordinator != oldWidget.coordinator ||
      unavailableReason != oldWidget.unavailableReason;
}
