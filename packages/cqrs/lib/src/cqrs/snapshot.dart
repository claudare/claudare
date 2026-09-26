/// Aggregate state after applying the event at [sequence].
/// This value does not provide serialization.
class Snapshot<T> {
  final T state;
  final int? sequence;

  const Snapshot(this.state, this.sequence);
}
