import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:time_provider/time_provider.dart';
import 'package:transport/transport.dart';

import 'actor/actor_identity_store.dart';
import 'replication/blob_replication/blob_replication_message_codec.dart';
import 'replication/blob_replication/blob_replicator.dart';
import 'replication/command_replication/command_replication_message_codec.dart';
import 'replication/command_replication/command_replicator.dart';
import 'sync_defaults.dart';
import 'sync_snapshot.dart';

const _commandsProtocol = 'commands';
const _blobsProtocol = 'blobs';

typedef TransportFactory = Transport Function();

/// Owns background transport and replication lifetimes.
///
/// Admits known peers when sessions start; removal leaves active sessions open.
/// Command and blob failures restart only that protocol on the same peer
/// connection after [reconnectInterval]. Injected stores remain open.
class SyncCoordinator {
  final EventStoreReplication eventStore;

  /// Storage shared with the command runtime. Null disables blob downloads and
  /// responds to blob requests with missing.
  final BlobStore? blobStore;
  final ActorIdentityStore identityStore;
  final TransportFactory createTransport;
  final Logger logger;
  final TimeProvider timeProvider;
  final Duration reconnectInterval;
  final Timer Function(Duration delay, void Function() callback) timerFactory;

  final Map<String, _PeerSession> _sessions = {};
  final _changes = StreamController<SyncSnapshot>.broadcast();
  SyncSnapshot _snapshot = SyncSnapshot(connection: SyncConnectionState.idle);
  Transport? _transport;
  StreamSubscription<PeerTransport>? _discovery;
  Timer? _reconnect;
  int _generation = 0;
  bool _started = false;
  bool _closed = false;

  SyncCoordinator({
    required this.eventStore,
    required this.identityStore,
    required this.createTransport,
    required this.logger,
    required this.timeProvider,
    this.blobStore,
    this.reconnectInterval = SyncDefaults.reconnectInterval,
    this.timerFactory = Timer.new,
  }) {
    if (reconnectInterval <= Duration.zero) {
      throw ArgumentError.value(
        reconnectInterval,
        'reconnectInterval',
        'Must be positive',
      );
    }
  }

  /// Current diagnostics, available before subscribing to [changes].
  SyncSnapshot get snapshot => _snapshot;

  /// Subsequent diagnostic snapshots. Closes when the coordinator closes.
  Stream<SyncSnapshot> get changes => _changes.stream;

  void _publish({SyncConnectionState? connection, String? failure}) {
    if (_changes.isClosed ||
        (_closed && connection != SyncConnectionState.closed)) {
      return;
    }
    _snapshot = SyncSnapshot(
      connection: connection ?? _snapshot.connection,
      activePeers: _sessions.values
          .where(
            (session) =>
                !session.closed &&
                (session.commandRunning || session.blobRunning),
          )
          .map((session) => session.peer.actor),
      lastFailure: failure ?? _snapshot.lastFailure,
      lastFailureAt: failure == null
          ? _snapshot.lastFailureAt
          : timeProvider.now().toUtc(),
    );
    _changes.add(_snapshot);
  }

  /// Starts background discovery, replication, and transport recovery once.
  void start() {
    if (_started || _closed) {
      throw StateError('SyncCoordinator cannot be started again');
    }
    _started = true;
    unawaited(_connect());
  }

  /// Initiates cleanup without waiting for transport or store operations.
  /// Repeated calls are safe. Restart requires a new coordinator.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _generation++;
      _reconnect?.cancel();
      _reconnect = null;
      _retireTransport();
      _publish(connection: SyncConnectionState.closed);
      unawaited(_changes.close());
    }
    return Future<void>.value();
  }

  bool _current(int generation) => !_closed && generation == _generation;

  Future<void> _connect() async {
    final generation = ++_generation;
    _publish(connection: SyncConnectionState.connecting);
    _scheduleRetry(attemptGeneration: generation);
    try {
      final transport = createTransport();
      _transport = transport;
      _discovery = transport.peerTransports.listen(
        (peer) => _discover(generation, peer),
        onError: (Object error, StackTrace stack) => _recover(generation),
        onDone: () => _recover(generation),
      );
      await transport.start();
      // Startup may complete after recovery or shutdown already closed it.
      if (!_current(generation)) {
        _cleanup(transport.close);
      } else {
        _reconnect?.cancel();
        _reconnect = null;
        _publish(connection: SyncConnectionState.connected);
      }
    } catch (error) {
      _recover(generation);
    }
  }

  void _recover(int generation) {
    if (!_current(generation)) return;
    _generation++;
    logger.warning('Sync transport ended; scheduling reconnect');
    _retireTransport();
    _publish(
      connection: SyncConnectionState.reconnecting,
      failure: 'Sync transport ended; scheduling reconnect',
    );
    _scheduleRetry();
  }

  void _scheduleRetry({int? attemptGeneration}) {
    _reconnect ??= timerFactory(reconnectInterval, () {
      _reconnect = null;
      if (_closed) return;
      if (attemptGeneration != null && _current(attemptGeneration)) {
        _generation++;
        logger.warning('Sync connection attempt timed out');
        _retireTransport();
        _publish(
          connection: SyncConnectionState.reconnecting,
          failure: 'Sync connection attempt timed out',
        );
      }
      unawaited(_connect());
    });
  }

  void _retireTransport() {
    final discovery = _discovery;
    final transport = _transport;
    _discovery = null;
    _transport = null;
    for (final session in _sessions.values.toList()) {
      _retireSession(session);
    }
    if (discovery != null) _cleanup(discovery.cancel);
    if (transport != null) _cleanup(transport.close);
  }

  bool _admitted(int generation, _PeerSession session) =>
      _current(generation) &&
      !session.closed &&
      identical(_sessions[session.peer.actor], session);

  void _discover(int generation, PeerTransport peer) {
    if (!_current(generation)) {
      _cleanup(peer.channel.sink.close);
      return;
    }
    final previous = _sessions[peer.actor];
    if (previous != null) _retireSession(previous);
    final session = _PeerSession(peer);
    _sessions[peer.actor] = session;
    unawaited(_admit(generation, session));
  }

  Future<void> _admit(int generation, _PeerSession session) async {
    try {
      // Buffer messages while checking membership, but observe closure now.
      session.messages = session.peer.channel.stream.listen(
        (message) {
          if (!session.closed) session.incoming.add(message);
        },
        onError: (Object error, StackTrace stack) {
          logger.error('Sync peer channel failed');
          if (_admitted(generation, session)) {
            _publish(failure: 'Sync peer channel failed');
          }
          _retireSession(session);
        },
        onDone: () => _retireSession(session),
      );
      unawaited(
        session.peer.channel.sink.done.then<void>(
          (_) => _retireSession(session),
          onError: (Object error, StackTrace stack) {
            logger.error('Sync peer channel failed');
            if (_admitted(generation, session)) {
              _publish(failure: 'Sync peer channel failed');
            }
            _retireSession(session);
          },
        ),
      );
      final peer = await identityStore.getPeer(
        PublicKey.fromString(session.peer.actor),
      );
      if (!_admitted(generation, session)) return;
      if (peer == null) {
        _retireSession(session);
        return;
      }
      final multiplexer = session.multiplexer = PeerMultiplexer(
        StreamChannel<String>(
          session.incoming.stream,
          session.peer.channel.sink,
        ),
      );
      session.commandSessions = multiplexer
          .sessions(_commandsProtocol)
          .listen((channel) => _commandSession(generation, session, channel));
      session.blobSessions = multiplexer
          .sessions(_blobsProtocol)
          .listen((channel) => _blobSession(generation, session, channel));
    } catch (error) {
      logger.error('Sync peer admission failed');
      if (_admitted(generation, session)) {
        _publish(failure: 'Sync peer admission failed');
      }
      _retireSession(session);
    }
  }

  void _commandSession(
    int generation,
    _PeerSession session,
    StreamChannel<String> channel,
  ) {
    if (!_admitted(generation, session) ||
        !identical(session.multiplexer!.channel(_commandsProtocol), channel)) {
      return;
    }
    final previous = session.commandReplicator;
    if (previous != null) _cleanup(previous.close);
    session.commandRunning = false;
    session.commandRestartTimer?.cancel();
    void start() {
      if (!_admitted(generation, session) ||
          !identical(
            session.multiplexer!.channel(_commandsProtocol),
            channel,
          )) {
        return;
      }
      session.commandRestartTimer = null;
      _startCommandReplication(generation, session, channel);
    }

    if (previous == null) {
      start();
    } else {
      session.commandRestartTimer = timerFactory(reconnectInterval, start);
      _publish();
    }
  }

  void _startCommandReplication(
    int generation,
    _PeerSession session,
    StreamChannel<String> channel,
  ) {
    if (!_admitted(generation, session) ||
        !identical(session.multiplexer!.channel(_commandsProtocol), channel)) {
      return;
    }
    final replicator = session.commandReplicator = CommandReplicator(
      channel: channel.transform(
        StreamChannelTransformer.fromCodec(
          const CommandReplicationMessageCodec(),
        ),
      ),
      eventStore: eventStore,
      logger: logger,
    );
    session.commandRunning = true;
    void ended({String? failure}) {
      if (!_admitted(generation, session) ||
          !identical(session.commandReplicator, replicator)) {
        return;
      }
      if (failure != null) logger.error(failure);
      session.commandRunning = false;
      _publish(failure: failure);
    }

    unawaited(
      replicator.run().then<void>(
        (_) => ended(),
        onError: (Object error, StackTrace stack) {
          ended(failure: 'Sync command replication failed');
        },
      ),
    );
    _publish();
  }

  void _blobSession(
    int generation,
    _PeerSession session,
    StreamChannel<String> channel,
  ) {
    if (!_admitted(generation, session) ||
        !identical(session.multiplexer!.channel(_blobsProtocol), channel)) {
      return;
    }
    final previous = session.blobReplicator;
    if (previous != null) _cleanup(previous.close);
    session.blobRunning = false;
    session.blobRestartTimer?.cancel();
    void start() {
      if (!_admitted(generation, session) ||
          !identical(session.multiplexer!.channel(_blobsProtocol), channel)) {
        return;
      }
      session.blobRestartTimer = null;
      _startBlobReplication(generation, session, channel);
    }

    if (previous == null) {
      start();
    } else {
      session.blobRestartTimer = timerFactory(reconnectInterval, start);
      _publish();
    }
  }

  void _startBlobReplication(
    int generation,
    _PeerSession session,
    StreamChannel<String> channel,
  ) {
    if (!_admitted(generation, session) ||
        !identical(session.multiplexer!.channel(_blobsProtocol), channel)) {
      return;
    }
    final replicator = session.blobReplicator = BlobReplicator(
      channel: channel.transform(
        StreamChannelTransformer.fromCodec(const BlobReplicationMessageCodec()),
      ),
      eventStore: eventStore,
      blobStore: blobStore,
      logger: logger,
      timerFactory: timerFactory,
    );
    session.blobRunning = true;
    void ended({String? failure}) {
      if (!_admitted(generation, session) ||
          !identical(session.blobReplicator, replicator)) {
        return;
      }
      if (failure != null) logger.error(failure);
      session.blobRunning = false;
      _publish(failure: failure);
    }

    unawaited(
      replicator.run().then<void>(
        (_) => ended(),
        onError: (Object error, StackTrace stack) {
          ended(failure: 'Sync blob replication failed');
        },
      ),
    );
    _publish();
  }

  void _retireSession(_PeerSession session) {
    if (session.closed) return;
    session.closed = true;
    if (identical(_sessions[session.peer.actor], session)) {
      _sessions.remove(session.peer.actor);
    }
    final commandReplicator = session.commandReplicator;
    final blobReplicator = session.blobReplicator;
    final messages = session.messages;
    final multiplexer = session.multiplexer;
    session.commandRestartTimer?.cancel();
    session.blobRestartTimer?.cancel();
    final commandSessions = session.commandSessions;
    final blobSessions = session.blobSessions;
    if (commandSessions != null) _cleanup(commandSessions.cancel);
    if (blobSessions != null) _cleanup(blobSessions.cancel);
    if (multiplexer != null) _cleanup(multiplexer.close);
    if (commandReplicator != null) _cleanup(commandReplicator.close);
    if (blobReplicator != null) _cleanup(blobReplicator.close);
    _cleanup(session.peer.channel.sink.close);
    if (messages != null) _cleanup(messages.cancel);
    if (multiplexer == null) {
      _cleanup(session.incoming.stream.listen(null).cancel);
    }
    _cleanup(session.incoming.close);
    _publish();
  }

  void _cleanup(Future<void> Function() operation) {
    unawaited(
      Future<void>.sync(operation).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          logger.error('Sync cleanup failed');
        },
      ),
    );
  }
}

class _PeerSession {
  final PeerTransport peer;
  final incoming = StreamController<String>();
  StreamSubscription<String>? messages;
  StreamSubscription<StreamChannel<String>>? commandSessions;
  StreamSubscription<StreamChannel<String>>? blobSessions;

  /// A restart delay on failure. This is to prevent spammy restarts.
  Timer? commandRestartTimer;

  /// A restart delay on failure. This is to prevent spammy restarts.
  Timer? blobRestartTimer;
  bool commandRunning = false;
  bool blobRunning = false;
  CommandReplicator? commandReplicator;
  BlobReplicator? blobReplicator;
  PeerMultiplexer? multiplexer;
  bool closed = false;

  _PeerSession(this.peer);
}
