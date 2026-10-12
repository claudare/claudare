import 'package:flutter/widgets.dart';
import 'package:sync/sync.dart';

/// Provides the current sync runtime.
class NoteSyncProvider extends InheritedWidget {
  final SyncCoordinator? coordinator;
  final String unavailableReason;

  /// Applies saved settings and refreshes the current sync runtime.
  final Future<void> Function() restartSync;

  const NoteSyncProvider({
    super.key,
    required super.child,
    required this.restartSync,
    this.coordinator,
    this.unavailableReason = 'Disabled',
  });

  static NoteSyncProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteSyncProvider>();

  static NoteSyncProvider of(BuildContext context) =>
      maybeOf(context) ?? (throw StateError('No NoteSyncProvider found'));

  @override
  bool updateShouldNotify(NoteSyncProvider oldWidget) =>
      coordinator != oldWidget.coordinator ||
      unavailableReason != oldWidget.unavailableReason ||
      restartSync != oldWidget.restartSync;
}
