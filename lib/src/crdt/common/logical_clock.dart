import 'dart:math';

import 'vector_logical_clock.dart';

typedef Counter = int;
typedef Actor = int;

// offline starts with a value of 0?
// then its synced as needed?
class TestLogicalClockOffline {
  final Actor actor;
  Counter offlineCounter;

  TestLogicalClockOffline(this.offlineCounter, this.actor);
  TestLogicalClockOffline.zero(this.actor) : offlineCounter = -1;

  LogicalClock current() {
    assert(offlineCounter != -1, 'no value yet');
    return LogicalClock(counter: offlineCounter, actor: actor);
  }

  LogicalClock next() {
    offlineCounter++;
    final newLogicalClock = LogicalClock(counter: offlineCounter, actor: actor);
    return newLogicalClock;
  }

  void syncWithVectorClock(VectorLogicalClock vectorClock) {
    if (offlineCounter > 0) {
      vectorClock.mergeLogicalClockMutate(current());
    }
    offlineCounter = vectorClock.maxCounterValue;
  }
}

// Try to use hybrid logical clocks (HLCs)
class LogicalClock {
  final Actor actor;
  final Counter counter;

  /// creates a logical clock with counter and actor
  // const LogicalClock(this.counter, this.actor);

  /// or use this to avoid confusion
  const LogicalClock({required this.actor, required this.counter});

  const LogicalClock.zero({required this.actor}) : counter = 0;

  factory LogicalClock.fromString(String value) {
    final parts = value.split('-');
    if (parts.length != 2) {
      throw FormatException('invalid id format', value);
    }

    final counter = int.parse(parts[0]);
    final actor = int.parse(parts[1]);

    return LogicalClock(counter: counter, actor: actor);
  }

  // it neever needs to clone with actor, actor stays constant
  //clone with optional params
  LogicalClock cloneWith({Counter? counter}) {
    // sanity check to make sure the counter never goes down
    if (counter != null) {
      assert(counter >= this.counter, 'counter should only increase');
    }

    return LogicalClock(counter: counter ?? this.counter, actor: actor);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LogicalClock) return false;
    return counter == other.counter && actor == other.actor;
  }

  @override
  int get hashCode => counter.hashCode ^ actor.hashCode;

  // compare the values
  int compareTo(LogicalClock other) {
    if (counter == other.counter) {
      return actor.compareTo(other.actor);
    }
    return counter.compareTo(other.counter);
  }

  @override
  String toString() {
    return '$counter-$actor';
  }
}
