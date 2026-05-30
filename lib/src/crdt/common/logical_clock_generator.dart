import 'logical_clock.dart';
import 'vector_logical_clock.dart';

/// [LogicalClockGenerator] mutates the underlying [VectorLogicalClock]
/// TODO: get rid of this, use
class LogicalClockGenerator {
  final Actor actor;
  final VectorLogicalClock _vectorClock;

  const LogicalClockGenerator(this._vectorClock, this.actor);

  /// generates a new LogicalClock and updates vector clock
  LogicalClock next() {
    final count = _vectorClock.maxCounterValue;
    final nextLogicalClock = LogicalClock(counter: count + 1, actor: actor);
    _vectorClock.mergeLogicalClockMutate(nextLogicalClock);
    return nextLogicalClock;
  }
}
