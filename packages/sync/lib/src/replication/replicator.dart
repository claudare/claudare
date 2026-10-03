import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:sync/sync.dart';

/// Continuously exchanges stored commands over one [ReplicationChannel].
///
/// Each writer must own a unique actor ID. Observe [run] for session failures
/// and use [close] to stop. A replicator cannot be restarted.
class Replicator {
  final ReplicationChannel _channel;
  final EventStoreReplication _eventStore;
  final Logger _logger;
  final Completer<void> _done = Completer<void>();

  StreamSubscription<ReplicationMessage>? _messages;
  StreamSubscription<CommandChange>? _changes;
  Future<void> _work = Future<void>.value();
  Future<void>? _closing;
  CommandDependency _peerKnowledge = CommandDependency();
  CommandId? _pending;
  bool _started = false;
  bool _closed = false;
  bool _receiving = false;
  bool _peerSubscribed = false;
  Object? _failure;
  StackTrace? _failureStack;

  Replicator({
    required this._channel,
    required this._eventStore,
    required this._logger,
  });

  /// Starts once and completes on closure, or fails with the original error.
  /// Set [receive] to false to send no subscription and accept no commands.
  Future<void> run({bool receive = true}) {
    if (_started) throw StateError('Replicator has already been started');
    _started = true;
    try {
      unawaited(_channel.sink.done.then<void>((_) {}, onError: _fail));
      _changes = _eventStore.commandChanges.listen(
        (_) => _enqueue(_sendNext),
        onError: _fail,
      );
      _enqueue(() async {
        if (!receive) return;
        final state = await _eventStore.getState();
        if (_closed) return;
        _receiving = true;
        _channel.sink.add(ReplicationMessageDependency(state.logVersion));
      });
      _messages = _channel.stream.listen(
        _onMessage,
        onError: _fail,
        onDone: () => unawaited(close()),
      );
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
    return _done.future;
  }

  /// Stops both directions and releases subscriptions and pending ACK state.
  /// Session failures are reported through [run]. Active store calls finish.
  Future<void> close() {
    if (!_started) throw StateError('Replicator has not been started');
    _closed = true;
    _pending = null;
    return _closing ??= Future<void>.microtask(_cleanup);
  }

  void _enqueue(Future<void> Function() action) {
    if (_closed) return;
    _work = _work.then((_) async {
      if (_closed) return;
      try {
        await action();
      } catch (error, stackTrace) {
        _fail(error, stackTrace);
      }
    });
  }

  void _onMessage(ReplicationMessage message) {
    if (_closed) return;
    if (message is ReplicationMessageCommand && !_receiving) {
      _fail(
        const ReplicationException('Command received without subscription'),
        StackTrace.current,
      );
      return;
    }
    if (message is ReplicationMessageCommandAck &&
        _pending != message.commandId) {
      _fail(
        const ReplicationException('Unexpected command ACK'),
        StackTrace.current,
      );
      return;
    }
    _enqueue(() => _receive(message));
  }

  Future<void> _receive(ReplicationMessage message) async {
    switch (message) {
      case ReplicationMessageDependency(:final version):
        if (_peerSubscribed) {
          throw const ReplicationException('Repeated subscription');
        }
        _merge(version);
        _peerSubscribed = true;
      case ReplicationMessageCommand(:final command):
        // Record knowledge before saving can publish a store change.
        _merge(command.dependency);
        _remember(command.commandId);
        if (!await _eventStore.addStoredCommand(command)) {
          throw const ReplicationException('Stored command was rejected');
        }
        if (_closed) return;
        _channel.sink.add(ReplicationMessageCommandAck(command.commandId));
      case ReplicationMessageCommandAck(:final commandId):
        if (_pending != commandId) {
          throw const ReplicationException('Unexpected command ACK');
        }
        _remember(commandId);
        _pending = null;
    }
    await _sendNext();
  }

  Future<void> _sendNext() async {
    if (_closed || !_peerSubscribed || _pending != null) return;
    final ids = await _eventStore.getNextCommandIds(_peerKnowledge, 1);
    if (_closed || ids.isEmpty) return;
    final command = await _eventStore.getStoredCommand(ids.single);
    if (_closed) return;
    if (command == null) {
      throw const ReplicationException(
        'Selected command is absent from the store',
      );
    }
    _pending = command.commandId;
    _channel.sink.add(ReplicationMessageCommand(command));
  }

  void _remember(CommandId id) =>
      _merge(CommandDependency({id.actor: id.sequence}));

  void _merge(CommandDependency dependency) {
    final values = Map<String, int>.of(_peerKnowledge.values);
    for (final entry in dependency.values.entries) {
      if (entry.value > (values[entry.key] ?? 0)) {
        values[entry.key] = entry.value;
      }
    }
    _peerKnowledge = CommandDependency(values);
  }

  void _recordFailure(Object error, StackTrace stackTrace) {
    if (_failure != null) return;
    _failure = error;
    _failureStack = stackTrace;
    _logger.error('Replication session failed');
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_done.isCompleted) return;
    _recordFailure(error, stackTrace);
    unawaited(close());
  }

  Future<void> _cleanup() async {
    // Start every cleanup operation even if another one fails.
    await Future.wait([
      _cleanupOperation(() => _channel.sink.close()),
      _cleanupOperation(() async => _messages?.cancel()),
      _cleanupOperation(() async => _changes?.cancel()),
    ]);
    await _work;
    final failure = _failure;
    if (failure == null) {
      _done.complete();
    } else {
      _done.completeError(failure, _failureStack);
    }
  }

  Future<void> _cleanupOperation(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      _recordFailure(error, stackTrace);
    }
  }
}
