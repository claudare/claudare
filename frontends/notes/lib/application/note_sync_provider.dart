import 'package:flutter/widgets.dart';
import 'package:sync/sync.dart';

/// Provides the current sync runtime and applies saved transport settings.
class NoteSyncProvider extends InheritedWidget {
  final SyncCoordinator? coordinator;
  final String unavailableReason;
  final Future<void> Function()? restartSync;

  const NoteSyncProvider({
    super.key,
    required super.child,
    this.coordinator,
    this.unavailableReason = 'Disabled',
    this.restartSync,
  });

  static NoteSyncProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteSyncProvider>();

  @override
  bool updateShouldNotify(NoteSyncProvider oldWidget) =>
      coordinator != oldWidget.coordinator ||
      unavailableReason != oldWidget.unavailableReason ||
      restartSync != oldWidget.restartSync;
}
