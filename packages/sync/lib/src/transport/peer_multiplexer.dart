import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

import 'multiplex_message.dart';

/// Routes independent command and blob sessions over one peer connection.
///
/// Closing a protocol session resets only that protocol on both peers. The
/// connection's keepalive and timeout remain shared. Transport failure or
/// [close] ends both protocols. Malformed envelopes are discarded.
class PeerMultiplexer {
  final StreamChannel<String> _peer;
  final _done = Completer<void>();
  late final _Protocol _commands;
  late final _Protocol _blobs;
  late final StreamSubscription<String> _subscription;
  bool _closed = false;

  PeerMultiplexer(this._peer) {
    unawaited(
      _done.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    _commands = _Protocol(this, PeerProtocol.commands);
    _blobs = _Protocol(this, PeerProtocol.blobs);
    _subscription = _peer.stream.listen(
      _receive,
      onError: _fail,
      onDone: close,
    );
    unawaited(
      _peer.sink.done.then<void>((_) {
        unawaited(close());
      }, onError: _fail),
    );
  }

  /// Current command session. Retired sessions cannot send into replacements.
  StreamChannel<String> get commands => _commands.current.channel;

  /// Current blob session. No blob transfer protocol is provided.
  StreamChannel<String> get blobs => _blobs.current.channel;

  /// Initial command session and replacements, buffered until subscribed.
  /// Skip retired entries by comparing them with [commands].
  Stream<StreamChannel<String>> get commandSessions =>
      _commands.sessions.stream;

  /// Initial blob session and replacements, buffered until subscribed.
  /// Skip retired entries by comparing them with [blobs].
  Stream<StreamChannel<String>> get blobSessions => _blobs.sessions.stream;

  void _receive(String message) {
    if (_closed) return;
    final MultiplexMessage envelope;
    try {
      envelope = MultiplexMessage.fromJson(jsonDecode(message));
    } on FormatException {
      return;
    }
    final protocol = switch (envelope.protocol) {
      PeerProtocol.commands => _commands,
      PeerProtocol.blobs => _blobs,
    };
    switch (envelope) {
      case MultiplexMessageReset(:final generation):
        if (generation > protocol.current.generation) {
          protocol.replace(generation);
        }
      case MultiplexMessageData(:final generation, :final data):
        if (generation == protocol.current.generation) {
          protocol.current.incoming.add(data);
        }
    }
  }

  void _send(MultiplexMessage message) {
    if (_closed) throw StateError('Peer connection is closed');
    try {
      _peer.sink.add(jsonEncode(message.toJson()));
    } catch (error, stack) {
      _fail(error, stack);
      rethrow;
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_closed) return;
    _commands.current.incoming.addError(error, stack);
    _blobs.current.incoming.addError(error, stack);
    unawaited(close());
  }

  /// Closes the connection and all sessions without waiting for consumers.
  /// Repeated calls return the same cleanup future.
  Future<void> close() {
    if (_closed) return _done.future;
    _closed = true;
    _commands.close();
    _blobs.close();
    _done.complete(
      Future.wait<void>([
        Future<void>.sync(_subscription.cancel),
        Future<void>.sync(_peer.sink.close),
      ]).then<void>((_) {}),
    );
    return _done.future;
  }
}

class _Protocol {
  final PeerMultiplexer owner;
  final PeerProtocol kind;
  final sessions = StreamController<StreamChannel<String>>();
  late _ProtocolSession current;

  _Protocol(this.owner, this.kind) {
    current = _ProtocolSession(this, 0);
    sessions.add(current.channel);
  }

  void restart(_ProtocolSession session) {
    if (owner._closed || !identical(current, session) || session.closed) return;
    final generation = session.generation + 1;
    owner._send(MultiplexMessageReset(protocol: kind, generation: generation));
    replace(generation);
  }

  void replace(int generation) {
    current.finish();
    current = _ProtocolSession(this, generation);
    sessions.add(current.channel);
  }

  void close() {
    current.finish();
    unawaited(sessions.close());
  }
}

class _ProtocolSession implements StreamSink<String> {
  final _Protocol protocol;
  final int generation;
  final _done = Completer<void>();
  late final StreamController<String> incoming;
  late final StreamChannel<String> channel;
  bool closed = false;
  bool _adding = false;

  _ProtocolSession(this.protocol, this.generation) {
    incoming = StreamController<String>(onCancel: close);
    channel = StreamChannel(incoming.stream, this);
  }

  @override
  Future<void> get done => _done.future;

  void _checkWritable() {
    if (closed) throw StateError('Protocol session is closed');
    if (_adding) throw StateError('Already adding a stream');
  }

  void _send(String data) => protocol.owner._send(
    MultiplexMessageData(
      protocol: protocol.kind,
      generation: generation,
      data: data,
    ),
  );

  @override
  void add(String data) {
    _checkWritable();
    _send(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _checkWritable();
    incoming.addError(error, stackTrace);
    unawaited(close());
  }

  @override
  Future<void> addStream(Stream<String> stream) async {
    _checkWritable();
    _adding = true;
    final completed = Completer<void>();
    StreamSubscription<String>? source;
    try {
      source = stream.listen(
        (data) {
          if (closed) return;
          try {
            _send(data);
          } catch (error, stack) {
            if (!completed.isCompleted) completed.completeError(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (closed) return;
          incoming.addError(error, stack);
          if (!completed.isCompleted) completed.completeError(error, stack);
          unawaited(close());
        },
        onDone: () {
          if (!completed.isCompleted) completed.complete();
        },
      );
      unawaited(
        done.then<void>((_) {
          if (!completed.isCompleted) completed.complete();
        }),
      );
      await completed.future;
    } finally {
      _adding = false;
      await source?.cancel();
    }
  }

  @override
  Future<void> close() {
    protocol.restart(this);
    return done;
  }

  void finish() {
    if (closed) return;
    closed = true;
    _done.complete();
    unawaited(incoming.close());
  }
}
