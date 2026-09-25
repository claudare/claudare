import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_context_api.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/stream_already_exists_exception.dart';
import 'package:cqrs/src/cqrs/exception/stream_not_found_exception.dart';
import 'package:time_provider/time_provider.dart';

part 'command_stream.dart';

/// Collects a command's ordered events, stream locks, and dependencies.
class CommandContext implements CommandContextApi {
  final EventStore _eventStore;
  final EventRegistry _eventRegistry;
  final TimeProvider _timeProvider;
  final Logger _logger;
  final DateTime _occuredAt;
  final List<EventAppend> _events = [];
  final Map<String, _CommandStreamState> _streams = {};
  final VersionVectorMutating _dependency = VersionVectorMutating();
  bool _finished = false;

  CommandContext({
    required EventStore eventStore,
    required EventRegistry eventRegistry,
    required TimeProvider timeProvider,
    required Logger logger,
  }) : _eventStore = eventStore,
       _eventRegistry = eventRegistry,
       _timeProvider = timeProvider,
       _logger = logger,
       _occuredAt = timeProvider.now();

  @override
  Logger get logger => _logger;

  VersionVector get dependency => _dependency.toVersionVector();

  @override
  CommandStream<TEvent> stream<TEvent extends Object>(String streamPath) {
    _ensureOpen();
    return CommandStream<TEvent>._(this, streamPath);
  }

  /// Seals this context and snapshots its changes.
  /// Throws [StateError] if acquisition is pending or the context is sealed.
  CommandChanges finish() {
    _ensureOpen();
    _finished = true;
    if (_streams.values.any((state) => state.pending)) {
      throw StateError('Stream acquisition is still pending');
    }

    return CommandChanges(
      dependency: dependency,
      occuredAt: _occuredAt,
      locks: List.unmodifiable(
        _streams.values.map((state) => state.lock).whereType<StreamLock>(),
      ),
      events: List.unmodifiable(_events),
    );
  }

  void _ensureOpen() {
    if (_finished) {
      throw StateError('Command context is sealed');
    }
  }

  void _beginAcquisition(String streamPath) {
    _ensureOpen();
    if (_streams.containsKey(streamPath)) {
      throw StateError('Stream already locked: $streamPath');
    }
    _streams[streamPath] = _CommandStreamState();
  }

  void _endAcquisition(String streamPath, StreamLock? lock) {
    if (_finished) return;
    final state = _streams[streamPath]!;
    state.pending = false;
    state.lock = lock;
  }

  Future<void> _lock(String streamPath, Future<int?> Function() acquire) async {
    _beginAcquisition(streamPath);
    StreamLock? lock;
    try {
      final version = await acquire();
      _ensureOpen();
      lock = StreamLock(
        streamPath: streamPath,
        originatingStreamVersion: version,
      );
    } finally {
      _endAcquisition(streamPath, lock);
    }
  }

  void _applyCommand(CommandId commandId) {
    _ensureOpen();
    _dependency.apply(commandId);
  }

  void _append(String streamPath, Object event) {
    _ensureOpen();
    if (_streams[streamPath]?.lock == null) {
      throw StateError('Stream not locked: $streamPath');
    }

    final occuredAt = _timeProvider.now();
    final encodedEvent = _eventRegistry.encode(event);
    _events.add(
      EventAppend(
        streamPath: streamPath,
        encodedEvent: encodedEvent,
        occuredAt: occuredAt,
      ),
    );
  }
}

class _CommandStreamState {
  bool pending = true;
  StreamLock? lock;
}
