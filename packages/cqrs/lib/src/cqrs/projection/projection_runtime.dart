import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/projection/projection_sink.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';
import 'package:queue/queue.dart';

import 'projection_failure_handler.dart';

class ProjectionRuntime<TEvent extends Object, TParams>
    implements ProjectionSink {
  final Projection<TEvent, TParams> _projection;
  final Logger _logger;
  final String _runtimeName;
  final int _runtimeVersion;
  final RuntimeStoreProjection _runtimeStore;
  final EventRegistry _eventRegistry;
  int _sequence = 0;

  late final AsyncFIFOQueue<QueueItem<TEvent, TParams>> _queue;

  ProjectionRuntime(
    this._projection, {
    required Logger logger,
    required String runtimeName,
    required int runtimeVersion,
    required RuntimeStoreProjection runtimeStore,
    required EventRegistry eventRegistry,
  }) : _logger = logger,
       _runtimeName = runtimeName,
       _runtimeVersion = runtimeVersion,
       _runtimeStore = runtimeStore,
       _eventRegistry = eventRegistry {
    validateProjection(_projection);
    _queue = AsyncFIFOQueue<QueueItem<TEvent, TParams>>(_handleApply);
  }

  String get projectionName => _projection.name;
  ProjectionFailureHandler get projectionFailureHandler =>
      _projection.failureHandler;

  bool isProjection(Projection projection) =>
      identical(_projection, projection);

  @override
  void enqueue(EventEnvelope eventEnvelope, {void Function()? onDone}) {
    final streamParams = _projection.streamRoute.parseParams(
      eventEnvelope.streamPath,
    );
    final event = _eventRegistry.decode<TEvent>(eventEnvelope.encodedEvent);
    _queue.enqueue(
      QueueItem(
        streamParams: streamParams,
        event: event,
        metadata: EventMetadata(occuredAt: eventEnvelope.occuredAt),
        localSequence: eventEnvelope.localSequence,
      ),
      onDone: onDone,
    );
  }

  @override
  void enqueueApplied(AppliedEvent appliedEvent, {void Function()? onDone}) {
    final streamParams = _projection.streamRoute.parseParams(
      appliedEvent.streamPath,
    );
    final event = _eventRegistry.decode<TEvent>(appliedEvent.encodedEvent);
    _queue.enqueue(
      QueueItem(
        streamParams: streamParams,
        event: event,
        metadata: EventMetadata(occuredAt: appliedEvent.occuredAt),
        localSequence: appliedEvent.localSequence,
      ),
      onDone: onDone,
    );
  }

  @override
  bool shouldProcess(String streamPath) {
    if (projectionFailureHandler.hasErrored()) {
      return false;
    }
    return _projection.streamRoute.matches(streamPath);
  }

  Future<void> resetProjection() async {
    try {
      _queue.reset();
      await _runtimeStore.resetProjection(_projection.name, _projection.reset);
      _sequence = 0;
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  Future<void> catchupSelfLoad(EventStore eventStore) async {
    if (projectionFailureHandler.hasErrored()) {
      return;
    }

    try {
      final position = await _runtimeStore.getProjectionPosition(
        _projection.name,
      );
      switch (position) {
        case ProjectionNotInitialized():
          _logger.warning(
            'runtime $_runtimeName@$_runtimeVersion: projection ${_projection.name} '
            'was not initialized during catch-up; resetting it',
          );
          await _runtimeStore.resetProjection(
            _projection.name,
            _projection.reset,
          );
          _sequence = 0;
        case ProjectionInconsistent():
          _logger.warning(
            'runtime $_runtimeName@$_runtimeVersion: projection ${_projection.name} '
            'was inconsistent during catch-up; resetting it',
          );
          await _runtimeStore.resetProjection(
            _projection.name,
            _projection.reset,
          );
          _sequence = 0;
        case ProjectionAtSequence(:final sequence):
          _sequence = sequence;
      }

      final reader = eventStore.getGlobalReader(
        _projection.streamRoute.filter,
        _sequence,
      );

      await for (final appliedEvent in reader.scan()) {
        final event = _eventRegistry.decode<TEvent>(appliedEvent.encodedEvent);
        final streamParams = _projection.streamRoute.parseParams(
          appliedEvent.streamPath,
        );
        await _advance(
          appliedEvent.localSequence,
          () => _projection.apply(
            streamParams,
            event,
            appliedEvent.eventMetadata,
          ),
        );
      }
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  Future<void> _handleApply(QueueItem<TEvent, TParams> item) async {
    assert(!projectionFailureHandler.hasErrored(), 'must not apply on error');
    if (projectionFailureHandler.hasErrored()) {
      return;
    }

    try {
      await _advance(
        item.localSequence,
        () => _projection.apply(item.streamParams, item.event, item.metadata),
      );
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  Future<void> _advance(
    int targetSequence,
    Future<void> Function() action,
  ) async {
    await _runtimeStore.advanceProjection(
      _projection.name,
      _sequence,
      targetSequence,
      action,
    );
    _sequence = targetSequence;
  }

  @override
  String toString() => 'ProjectionRuntime(${_projection.name})';
}

void validateProjection(Projection projection) {
  if (projection.name.trim().isEmpty) {
    throw const ProjectionConfigurationException(
      'Projection name must not be empty',
    );
  }
  if (projection.name != projection.name.trim()) {
    throw ProjectionConfigurationException(
      'Projection name ${projection.name} must not have surrounding whitespace',
    );
  }
  if (projection.version <= 0) {
    throw ProjectionConfigurationException(
      'Projection ${projection.name} must have a positive version',
    );
  }
  if (projection.streamRoute.pattern.trim().isEmpty) {
    throw ProjectionConfigurationException(
      'Projection ${projection.name} has an empty stream route pattern',
    );
  }
}

final class QueueItem<TEvent extends Object, TParams> {
  final TParams streamParams;
  final TEvent event;
  final EventMetadata metadata;
  final int localSequence;

  const QueueItem({
    required this.streamParams,
    required this.event,
    required this.metadata,
    required this.localSequence,
  });
}
