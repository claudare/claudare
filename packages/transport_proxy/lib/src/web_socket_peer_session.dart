import 'dart:async';

import 'package:stream_channel/stream_channel.dart';

/// Internal state and channel ownership for one proxy peer session.
class WebSocketPeerSession {
  final String actor;
  final String id;
  DateTime lastReceived;
  Timer? activityTimer;
  Timer? expiryTimer;
  bool established = false;
  bool closed = false;
  late final StreamController<String> _incoming;
  late final _PeerSink _sink;
  late final StreamChannel<String> channel;

  WebSocketPeerSession({
    required this.actor,
    required this.id,
    required this.lastReceived,
    required void Function(String) send,
    required void Function() onClose,
  }) {
    _incoming = StreamController<String>(onCancel: onClose);
    _sink = _PeerSink(send, onClose);
    channel = StreamChannel.withCloseGuarantee(_incoming.stream, _sink);
  }

  void receive(String data) {
    if (!closed) _incoming.add(data);
  }

  void close() {
    if (closed) return;
    closed = true;
    activityTimer?.cancel();
    expiryTimer?.cancel();
    _sink.disconnect();
    unawaited(_incoming.close());
  }
}

class _PeerSink implements StreamSink<String> {
  final void Function(String) _send;
  final void Function() _onClose;
  final _done = Completer<void>();
  bool _closed = false;
  StreamSubscription<String>? _source;
  Completer<void>? _adding;

  _PeerSink(this._send, this._onClose);

  @override
  Future<void> get done => _done.future;

  @override
  void add(String data) {
    if (_done.isCompleted) throw StateError('Peer session is closed');
    if (_adding != null) throw StateError('Already adding a stream');
    _send(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) throw StateError('Peer session is closed');
    if (_adding != null) throw StateError('Already adding a stream');
    _done.completeError(error, stackTrace);
    _onClose();
  }

  @override
  Future<void> addStream(Stream<String> stream) {
    if (_done.isCompleted) throw StateError('Peer session is closed');
    if (_adding != null) throw StateError('Already adding a stream');
    final adding = _adding = Completer<void>();
    _source = stream.listen(
      _send,
      onError: (Object error, StackTrace stack) {
        if (!adding.isCompleted) adding.completeError(error, stack);
        _onClose();
      },
      onDone: () {
        _source = null;
        _adding = null;
        if (!adding.isCompleted) adding.complete();
      },
    );
    return adding.future;
  }

  @override
  Future<void> close() {
    _onClose();
    return done;
  }

  void disconnect() {
    if (_closed) return;
    _closed = true;
    final source = _source;
    _source = null;
    final adding = _adding;
    _adding = null;
    if (source != null) {
      unawaited(
        source.cancel().then((_) {
          if (adding != null && !adding.isCompleted) adding.complete();
        }),
      );
    }
    if (!_done.isCompleted) _done.complete();
  }
}
