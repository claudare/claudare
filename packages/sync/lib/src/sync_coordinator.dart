import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';

import 'actor/actor_identity_store.dart';
import 'transport/transport.dart';

typedef TransportFactory = Transport Function();

/// Planned owner of background transport and replication lifetimes.
///
/// Admits known peers when sessions start; removal leaves active sessions open.
/// Replication failures are handled internally. Not yet implemented.
class SyncCoordinator {
  final EventStoreReplication eventStore;
  final ActorIdentityStore identityStore;
  final TransportFactory createTransport;
  final Logger logger;
  final Duration reconnectDelay;
  final Timer Function(Duration delay, void Function() callback) timerFactory;

  SyncCoordinator({
    required this.eventStore,
    required this.identityStore,
    required this.createTransport,
    required this.logger,
    this.reconnectDelay = const Duration(seconds: 5),
    this.timerFactory = Timer.new,
  });

  /// Starts background discovery, replication, and transport recovery once.
  void start() => throw UnimplementedError();

  /// Stops background work and awaits cleanup; leaves injected stores open.
  /// Repeated calls are intended to be safe.
  Future<void> close() => throw UnimplementedError();
}
