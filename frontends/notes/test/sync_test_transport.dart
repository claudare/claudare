import 'dart:async';

import 'package:sync/sync.dart';

/// Controllable transport with no sockets or timers.
class TestTransport implements Transport {
  final discovery = StreamController<PeerTransport>();
  Future<void> Function()? onStart;
  void Function()? onClose;
  int starts = 0;
  bool closed = false;

  @override
  Stream<PeerTransport> get peerTransports => discovery.stream;

  @override
  Future<void> start() async {
    starts++;
    await onStart?.call();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    onClose?.call();
    await discovery.close();
  }
}
