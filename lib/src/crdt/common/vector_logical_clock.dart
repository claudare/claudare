import 'dart:math' show max;

import 'package:core/src/crdt/common/logical_clock_generator.dart';

import 'logical_clock.dart';

class VectorLogicalClock {
  final Map<Actor, Counter> _vectorMap;
  Counter _maxCounterValue;

  VectorLogicalClock(this._vectorMap)
    : _maxCounterValue = _vectorMap.values.reduce(max);

  VectorLogicalClock.empty()
    : _vectorMap = {},
      _maxCounterValue = -1; // TODO: empty is 0?

  LogicalClockGenerator getGenerator(Actor actor) {
    return LogicalClockGenerator(this, actor);
  }

  factory VectorLogicalClock.fromLogicalClocks(List<LogicalClock> clocks) {
    final map = <Actor, Counter>{};

    for (final clock in clocks) {
      map[clock.actor] = clock.counter;
    }

    return VectorLogicalClock(map);
  }

  // shortcut for generator-less operation
  // LogicalClock nextId(Actor actor) {
  //   final count = _vectorMap[actor] ?? -1;
  //   final newLogicalClock = LogicalClock(counter: count + 1, actor: actor);
  //   mergeMutate(newLogicalClock);
  //   return newLogicalClock;
  // }

  void mergeLogicalClockMutate(LogicalClock clock) {
    if (clock.counter > _maxCounterValue) {
      _maxCounterValue = clock.counter;
    }
    _vectorMap[clock.actor] = clock.counter;
  }

  // TODO: try not to expose this
  int get maxCounterValue => _maxCounterValue;

  LogicalClock operator [](Actor actor) {
    // dont allow non-existing clocks?
    final counter = _vectorMap[actor];
    if (counter == null) {
      throw Exception('actor $actor is not in vector logical clock');
    }
    return LogicalClock(counter: counter, actor: actor);
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
          .map(
            (entry) =>
                LogicalClock(actor: entry.key, counter: entry.value).toString(),
          )
          .toList();

  @override
  String toString() {
    return '[VectorLogicalClock](${_vectorMap.entries.map((entry) => LogicalClock(actor: entry.key, counter: entry.value).toString()).join(', ')})';
  }
}
