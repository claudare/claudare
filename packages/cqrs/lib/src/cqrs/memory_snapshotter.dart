import 'package:cqrs/src/cqrs/snapshotter.dart';

/// State that can make a detached copy of itself for a [MemorySnapshotter].
abstract interface class SnapshotCloneable<T> {
  T clone();
}

/// Keeps one aggregate snapshot in memory.
/// Use one instance for each aggregate selection and event store.
class MemorySnapshotter<T extends SnapshotCloneable<T>>
    implements Snapshotter<T> {
  Snapshot<T>? _snapshot;
  int? _version;

  @override
  Future<Snapshot<T>?> load(int aggregateVersion) async {
    final snapshot = _snapshot;
    if (_version != aggregateVersion || snapshot == null) return null;
    return Snapshot(snapshot.state.clone(), snapshot.sequence);
  }

  @override
  Future<void> save(int aggregateVersion, Snapshot<T> snapshot) async {
    final stored = Snapshot(snapshot.state.clone(), snapshot.sequence);
    _snapshot = stored;
    _version = aggregateVersion;
  }
}
