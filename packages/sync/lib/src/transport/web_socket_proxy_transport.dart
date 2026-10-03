import 'dart:async';
import 'dart:convert';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:id_generator/id_generator.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:time_provider/time_provider.dart';
import 'package:web_socket_channel/io.dart';

import '../proxy/proxy_init.dart';
import '../proxy/proxy_message.dart';
import 'transport.dart';
import 'transport_message.dart';
import 'web_socket_peer_session.dart';

/// Opens a ready connection using the supplied proxy initialization headers.
typedef ProxyConnectionOpener = Future<StreamChannel<Object?>> Function(
  String url,
  Map<String, String> headers,
);

/// Creates a cancellable, one-shot timer.
typedef TransportTimerFactory = Timer Function(Duration delay, void Function());

/// Discovers peer sessions through one live WebSocket proxy connection.
/// Subscribe to [peerTransports] before [start]. Socket closure is terminal.
class WebSocketProxyTransport implements Transport {
  final String _baseUrl;
  final String _thisActor;
  final String _group;
  final Logger _logger;
  final IdGenerator _idGenerator;
  final TimeProvider _timeProvider;
  final ProxyConnectionOpener _openConnection;
  final TransportTimerFactory _timerFactory;
  final Duration _discoveryInterval;
  final Duration _keepaliveInterval;
  final Duration _sessionTimeout;
  final _peers = StreamController<PeerTransport>();
  final _sessions = <String, WebSocketPeerSession>{};
  StreamChannel<Object?>? _socket;
  StreamSubscription<Object?>? _messages;
  Timer? _discovery;
  bool _started = false;
  bool _closed = false;
  Future<void>? _closing;

  WebSocketProxyTransport({
    required this._baseUrl,
    required String thisActor,
    required String group,
    required this._logger,
    required this._idGenerator,
    required this._timeProvider,
    this._openConnection = _connect,
    this._timerFactory = Timer.new,
    Duration discoveryInterval = const Duration(seconds: 5),
    Duration keepaliveInterval = const Duration(seconds: 5),
    Duration sessionTimeout = const Duration(seconds: 15),
  }) : _thisActor = thisActor,
       _group = group,
       _discoveryInterval = discoveryInterval,
       _keepaliveInterval = keepaliveInterval,
       _sessionTimeout = sessionTimeout {
    if (thisActor.trim().isEmpty || group.trim().isEmpty) {
      throw ArgumentError('Actor and group must be nonempty');
    }
    if (discoveryInterval <= Duration.zero ||
        keepaliveInterval <= Duration.zero ||
        sessionTimeout <= keepaliveInterval) {
      throw ArgumentError(
        'Intervals must be positive and timeout must exceed keepalive',
      );
    }
    _peers.onCancel = close;
  }

  static Future<StreamChannel<Object?>> _connect(
    String url,
    Map<String, String> headers,
  ) async {
    final socket = IOWebSocketChannel.connect(url, headers: headers);
    try {
      await socket.ready;
      return socket.cast<Object?>();
    } on Exception {
      await socket.sink.close();
      rethrow;
    }
  }

  @override
  Stream<PeerTransport> get peerTransports => _peers.stream;

  @override
  Future<void> start() async {
    if (_started || _closed) {
      throw StateError('Transport cannot be started again');
    }
    _started = true;
    try {
      final socket = await _openConnection(
        _baseUrl,
        ProxyInit(actor: _thisActor, group: _group).toHeaders(),
      );
      if (_closed) {
        await socket.sink.close();
        return;
      }
      _socket = socket;
      _messages = socket.stream.listen(
        _receive,
        onError: _fail,
        onDone: () => unawaited(close()),
      );
      unawaited(socket.sink.done.then<void>((_) => close(), onError: _fail));
      _write(_thisActor, const TransportMessageDiscovery(), broadcast: true);
      _discovery = _timerFactory(_discoveryInterval, _sendDiscovery);
      _logger.info('Proxy transport started');
    } on Exception {
      await close();
      rethrow;
    }
  }

  void _sendDiscovery() {
    if (_closed) return;
    _send(_thisActor, const TransportMessageDiscovery(), broadcast: true);
    if (!_closed) {
      _discovery = _timerFactory(_discoveryInterval, _sendDiscovery);
    }
  }

  void _send(String actor, TransportMessage message, {bool broadcast = false}) {
    if (_closed) return;
    try {
      _write(actor, message, broadcast: broadcast);
    } on Exception catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _write(
    String actor,
    TransportMessage message, {
    bool broadcast = false,
  }) {
    _socket!.sink.add(
      jsonEncode(
        ProxyMessage(
          type: broadcast
              ? ProxyMessageType.broadcast
              : ProxyMessageType.direct,
          actor: actor,
          data: jsonEncode(message.toJson()),
        ).toJson(),
      ),
    );
  }

  void _receive(Object? frame) {
    if (_closed) return;
    final ProxyMessage proxy;
    final TransportMessage message;
    try {
      if (frame is! String) throw const FormatException('Expected text frame');
      proxy = ProxyMessage.fromJson(jsonDecode(frame));
      message = TransportMessage.fromJson(jsonDecode(proxy.data));
    } on FormatException {
      _logger.warning('Ignored malformed proxy transport message');
      return;
    }
    final actor = proxy.actor;
    if (actor == _thisActor || actor.trim().isEmpty) return;
    if (message is TransportMessageDiscovery) {
      if (_thisActor.compareTo(actor) < 0) {
        if (!_sessions.containsKey(actor)) {
          final session = _create(actor, _idGenerator.generateId());
          _send(actor, TransportMessageHandshake(session.id));
        }
      } else if (proxy.type == ProxyMessageType.broadcast) {
        _send(actor, const TransportMessageDiscovery());
      }
      return;
    }
    if (proxy.type != ProxyMessageType.direct) return;
    if (message is TransportMessageHandshake) {
      if (actor.compareTo(_thisActor) >= 0) {
        return;
      }
      var session = _sessions[actor];
      if (session?.id != message.sessionId) {
        if (session != null) _end(session);
        session = _create(actor, message.sessionId);
      }
      _send(actor, TransportMessageHandshakeAck(message.sessionId));
      if (!_closed) _establish(session!);
      return;
    }
    final session = _sessions[actor];
    if (session == null) return;
    switch (message) {
      case TransportMessageHandshakeAck(:final sessionId):
        if (session.id == sessionId && _thisActor.compareTo(actor) < 0) {
          _establish(session);
        }
      case TransportMessageData(:final sessionId, :final data):
        if (session.id == sessionId && session.established) {
          _refresh(session);
          session.receive(data);
        }
      case TransportMessageKeepalive(:final sessionId):
        if (session.id == sessionId && session.established) _refresh(session);
      case TransportMessageClose(:final sessionId):
        if (session.id == sessionId) _end(session);
      case TransportMessageDiscovery() || TransportMessageHandshake():
        break;
    }
  }

  WebSocketPeerSession _create(String actor, String id) {
    late final WebSocketPeerSession session;
    session = WebSocketPeerSession(
      actor: actor,
      id: id,
      lastReceived: _timeProvider.now(),
      send: (data) =>
          _send(actor, TransportMessageData(sessionId: id, data: data)),
      onClose: () => _end(session, notify: true),
    );
    _sessions[actor] = session;
    _refresh(session);
    return session;
  }

  void _establish(WebSocketPeerSession session) {
    if (session.closed || session.established) return;
    session.established = true;
    _refresh(session);
    _keepalive(session);
    _peers.add(PeerTransport(actor: session.actor, channel: session.channel));
    _logger.debug('Peer session established');
  }

  void _keepalive(WebSocketPeerSession session) {
    if (session.closed) return;
    session.activityTimer = _timerFactory(_keepaliveInterval, () {
      _send(session.actor, TransportMessageKeepalive(session.id));
      _keepalive(session);
    });
  }

  void _refresh(WebSocketPeerSession session) {
    session.lastReceived = _timeProvider.now();
    session.expiryTimer?.cancel();
    session.expiryTimer = _timerFactory(
      _sessionTimeout,
      () => _expire(session),
    );
  }

  void _expire(WebSocketPeerSession session) {
    if (session.closed) return;
    final remaining =
        _sessionTimeout - _timeProvider.now().difference(session.lastReceived);
    if (remaining > Duration.zero) {
      session.expiryTimer = _timerFactory(remaining, () => _expire(session));
    } else {
      _logger.debug('Peer session timed out');
      _end(session, notify: true);
    }
  }

  void _end(WebSocketPeerSession session, {bool notify = false}) {
    if (session.closed) return;
    _sessions.remove(session.actor);
    session.close();
    if (notify) _send(session.actor, TransportMessageClose(session.id));
    _logger.debug('Peer session closed');
  }

  void _fail(Object error, StackTrace stack) {
    if (error is Error) Error.throwWithStackTrace(error, stack);
    if (_closed) return;
    _logger.error('Proxy transport failed');
    _peers.addError(error, stack);
    unawaited(close());
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _closing = Future<void>.microtask(() async {
      _discovery?.cancel();
      for (final session in _sessions.values.toList()) {
        _end(session);
      }
      // Stream completion must not wait for a consumer to attach or resume.
      unawaited(_peers.close());
      await Future.wait([
        _cleanup(() async => _messages?.cancel()),
        _cleanup(() async => _socket?.sink.close()),
      ]);
      _logger.info('Proxy transport closed');
    });
    return _closing!;
  }

  Future<void> _cleanup(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      _logger.warning('Proxy connection cleanup failed');
    }
  }
}
