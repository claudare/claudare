import 'dart:async';

import 'package:time_provider/time_provider.dart';

class TestClock implements TimeProvider {
  DateTime _now = DateTime.utc(2026);
  final _timers = <_TestTimer>[];

  @override
  DateTime now() => _now;

  Timer schedule(Duration delay, void Function() callback) {
    final timer = _TestTimer(_now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  int get activeTimers => _timers.where((timer) => timer.isActive).length;

  Future<void> elapse(Duration duration) async {
    final target = _now.add(duration);
    while (true) {
      _timers.removeWhere((timer) => !timer.isActive);
      _timers.sort((a, b) => a.at.compareTo(b.at));
      if (_timers.isEmpty || _timers.first.at.isAfter(target)) break;
      final timer = _timers.removeAt(0);
      _now = timer.at;
      timer.fire();
      await flushMessages();
    }
    _now = target;
    await flushMessages();
  }
}

class _TestTimer implements Timer {
  final DateTime at;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  _TestTimer(this.at, this.callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

Future<void> flushMessages() => Future<void>.delayed(Duration.zero);
