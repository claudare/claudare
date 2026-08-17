import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/projection/projection_route.dart';
import 'package:cqrs/src/cqrs/projection/projection_sink.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';
import 'package:queue/queue.dart';

import 'projection_failure_handler.dart';

class ProjectionRuntime implements ProjectionSink {
  final Projection _projection;
  final List<ProjectionRoute> _routes;
  final Logger _logger;
  final String _runtimeName;
  final int _runtimeVersion;
  final RuntimeStoreProjection _runtimeStore;
  final EventRegistry _eventRegistry;
  int _sequence = 0;

  late final AsyncFIFOQueue<QueueItem> _queue;

  ProjectionRuntime(
    this._projection, {
    required Logger logger,
    required String runtimeName,
    required int runtimeVersion,
    required RuntimeStoreProjection runtimeStore,
    required EventRegistry eventRegistry,
  }) : _routes = List.unmodifiable(_projection.routes),
       _logger = logger,
       _runtimeName = runtimeName,
       _runtimeVersion = runtimeVersion,
       _runtimeStore = runtimeStore,
       _eventRegistry = eventRegistry {
    validateProjection(_projection, _routes);
    _queue = AsyncFIFOQueue<QueueItem>((value) => _handleApply(value));
  }

  String get projectionName => _projection.name;
  ProjectionFailureHandler get projectionFailureHandler =>
      _projection.failureHandler;

  bool isProjection(Projection projection) =>
      identical(_projection, projection);

  @override
  void enqueue(EventEnvelope eventEnvelope, {void Function()? onDone}) {
    final event = _eventRegistry.decodeObject(eventEnvelope.encodedEvent);
    _queue.enqueue(
      QueueItem(
        streamPath: eventEnvelope.streamPath,
        event: event,
        metadata: EventMetadata(occuredAt: eventEnvelope.occuredAt),
        localSequence: eventEnvelope.localSequence,
      ),
      onDone: onDone,
    );
  }

  @override
  void enqueueApplied(AppliedEvent appliedEvent, {void Function()? onDone}) {
    final event = _eventRegistry.decodeObject(appliedEvent.encodedEvent);
    _queue.enqueue(
      QueueItem(
        streamPath: appliedEvent.streamPath,
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

    return _routes.any((route) => route.streamRoute.matches(streamPath));
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
        const PatternFilter.any(),
        _sequence,
      );

      await for (final appliedEvent in reader.scan()) {
        if (!shouldProcess(appliedEvent.streamPath)) {
          continue;
        }

        final event = _eventRegistry.decodeObject(appliedEvent.encodedEvent);
        await _advance(
          appliedEvent.localSequence,
          () => _applyMatchingRoutes(
            appliedEvent.streamPath,
            event,
            appliedEvent.eventMetadata,
          ),
        );
      }
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  Future<void> _handleApply(QueueItem item) async {
    assert(!projectionFailureHandler.hasErrored(), 'must not apply on error');
    if (projectionFailureHandler.hasErrored()) {
      return;
    }

    try {
      await _advance(
        item.localSequence,
        () => _applyMatchingRoutes(item.streamPath, item.event, item.metadata),
      );
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  Future<void> _applyMatchingRoutes(
    String streamPath,
    Object event,
    EventMetadata metadata,
  ) async {
    for (final route in _routes) {
      if (route.matches(streamPath, event)) {
        await route.apply(streamPath, event, metadata);
      }
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

void validateProjection(Projection projection, List<ProjectionRoute> routes) {
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
  if (routes.isEmpty) {
    throw ProjectionConfigurationException(
      'Projection ${projection.name} must define at least one route',
    );
  }

  for (final route in routes) {
    if (route.streamRoute.pattern.trim().isEmpty) {
      throw ProjectionConfigurationException(
        'Projection ${projection.name} has a route with an empty pattern',
      );
    }
  }
}

final class QueueItem {
  final String streamPath;
  final Object event;
  final EventMetadata metadata;
  final int localSequence;

  const QueueItem({
    required this.streamPath,
    required this.event,
    required this.metadata,
    required this.localSequence,
  });
}
