/// Aggregate state after applying the event at [sequence].
class Snapshot<T> {
  final T state;
  final int sequence;

  const Snapshot(this.state, this.sequence);
}

/// Stores snapshots scoped to one aggregate selection and event store.
/// Implementations must isolate mutable state on both load and save.
abstract interface class Snapshotter<T> {
  /// Returns fresh state for this version, or null if no compatible snapshot exists.
  Future<Snapshot<T>?> load(int aggregateVersion);

  /// Stores a detached copy of the state for this version.
  Future<void> save(int aggregateVersion, Snapshot<T> snapshot);
}
