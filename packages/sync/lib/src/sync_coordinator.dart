import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:time_provider/time_provider.dart';

import 'actor/actor_identity_store.dart';
import 'replication/replication_message_codec.dart';
import 'replication/replicator.dart';
import 'sync_defaults.dart';
import 'sync_snapshot.dart';
import 'transport/transport.dart';

typedef TransportFactory = Transport Function();

/// Owns background transport and replication lifetimes.
///
/// Admits known peers when sessions start; removal leaves active sessions open.
/// Replication failures are handled internally. Injected stores remain open.
class SyncCoordinator {
  final EventStoreReplication eventStore;
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
          .where((session) => session.replicator != null && !session.closed)
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
      final channel =
          StreamChannel<String>(
            session.incoming.stream,
            session.peer.channel.sink,
          ).transform(
            StreamChannelTransformer.fromCodec(const ReplicationMessageCodec()),
          );
      final replicator = session.replicator = Replicator(
        channel: channel,
        eventStore: eventStore,
        logger: logger,
      );
      unawaited(
        replicator.run().then<void>(
          (_) => _retireSession(session),
          onError: (Object error, StackTrace stack) {
            logger.error('Sync replication failed');
            if (_current(generation) &&
                (_sessions[session.peer.actor] == null ||
                    identical(_sessions[session.peer.actor], session))) {
              _publish(failure: 'Sync replication failed');
            }
            _retireSession(session);
          },
        ),
      );
      _publish();
    } catch (error) {
      logger.error('Sync peer admission failed');
      if (_admitted(generation, session)) {
        _publish(failure: 'Sync peer admission failed');
      }
      _retireSession(session);
    }
  }

  void _retireSession(_PeerSession session) {
    if (session.closed) return;
    session.closed = true;
    if (identical(_sessions[session.peer.actor], session)) {
      _sessions.remove(session.peer.actor);
    }
    final replicator = session.replicator;
    final messages = session.messages;
    if (replicator != null) _cleanup(replicator.close);
    _cleanup(session.peer.channel.sink.close);
    if (messages != null) _cleanup(messages.cancel);
    if (replicator == null) {
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
  Replicator? replicator;
  bool closed = false;

  _PeerSession(this.peer);
}
