import 'dart:math';

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
    return LogicalClock(offlineCounter, actor);
  }

  LogicalClock next() {
    offlineCounter++;
    final newLogicalClock = LogicalClock(offlineCounter, actor);
    return newLogicalClock;
  }

  void syncWithVectorClock(VectorLogicalClock vectorClock) {
    if (offlineCounter > 0) {
      vectorClock.logicalClockUpdate(current());
    }
    offlineCounter = vectorClock._maxCounterValue;
  }
}

class LogicalClockGenerator {
  final Actor actor;
  final VectorLogicalClock _vectorClock;

  LogicalClockGenerator(this._vectorClock, this.actor);

  /// generates a new LogicalClock and updates vector clock
  LogicalClock next() {
    final count = _vectorClock._maxCounterValue;
    final newLogicalClock = LogicalClock(count + 1, actor);
    _vectorClock.logicalClockUpdate(newLogicalClock);
    return newLogicalClock;
  }
}

class VectorLogicalClock {
  final Map<Actor, Counter> _vectorMap;
  Counter _maxCounterValue;

  VectorLogicalClock(this._vectorMap)
    : _maxCounterValue = _vectorMap.values.reduce(max);

  VectorLogicalClock.empty() : _vectorMap = {}, _maxCounterValue = -1;

  factory VectorLogicalClock.fromLogicalClocks(List<LogicalClock> clocks) {
    final map = <Actor, Counter>{};

    for (final clock in clocks) {
      map[clock.actor] = clock.counter;
    }

    return VectorLogicalClock(map);
  }

  // shortcut for generator-less operation
  LogicalClock nextOpId(Actor actor) {
    final count = _vectorMap[actor] ?? -1;
    final newLogicalClock = LogicalClock(count + 1, actor);
    logicalClockUpdate(newLogicalClock);
    return newLogicalClock;
  }

  LogicalClockGenerator getGenerator(Actor actor) {
    return LogicalClockGenerator(this, actor);
  }

  void logicalClockUpdate(LogicalClock clock) {
    if (clock.counter > _maxCounterValue) {
      _maxCounterValue = clock.counter;
    }
    _vectorMap[clock.actor] = clock.counter;
  }

  // dont use this really? most updates should happen through methods
  int get maxCounterValue => _maxCounterValue;

  LogicalClock operator [](Actor actor) {
    // dont allow non-existing clocks?
    final counter = _vectorMap[actor];
    if (counter == null) {
      throw Exception('actor $actor is not in vector logical clock');
    }
    return LogicalClock(counter, actor);
  }

  /// returns true if the value is less then or equal to the vector clock
  bool isVisible(LogicalClock value) {
    return _vectorMap[value.actor] != null &&
        value.counter <= _vectorMap[value.actor]!;
  }

  factory VectorLogicalClock.fromJson(List<dynamic> json) {
    final Map<Actor, Counter> out = {};
    for (final entry in json) {
      final lc = LogicalClock.fromString(entry);
      out[lc.actor] = lc.counter;
    }
    return VectorLogicalClock(out);
  }

  List<String> toJson() =>
      _vectorMap.entries
          .map((entry) => LogicalClock(entry.value, entry.key).toString())
          .toList();

  @override
  String toString() {
    return '[VectorLogicalClock](${_vectorMap.entries.map((entry) => LogicalClock(entry.value, entry.key).toString()).join(', ')})';
  }
}

// Try to use hybrid logical clocks (HLCs)
class LogicalClock {
  final Counter counter;
  final Actor actor;

  /// creates a logical clock with counter and actor
  const LogicalClock(this.counter, this.actor);

  /// or use this to avoid confusion
  const LogicalClock.explicit({required Counter counter, required Actor actor})
    : this(counter, actor);

  LogicalClock.zero(this.actor) : counter = 0;

  factory LogicalClock.fromString(String value) {
    final parts = value.split('-');
    if (parts.length != 2) {
      throw FormatException('invalid id format', value);
    }

    final counter = int.parse(parts[0]);
    final actor = int.parse(parts[1]);

    return LogicalClock(counter, actor);
  }

  // it neever needs to clone with actor, actor stays constant
  //clone with optional params
  LogicalClock cloneWith({Counter? counter}) {
    // sanity check to make sure the counter never goes down
    if (counter != null) {
      assert(counter >= this.counter, 'counter should only increase');
    }

    return LogicalClock(counter ?? this.counter, actor);
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
