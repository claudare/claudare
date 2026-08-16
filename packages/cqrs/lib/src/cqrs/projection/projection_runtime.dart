import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/projection/projection_sink.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:queue/queue.dart';

import 'projection_failure_handler.dart';

class ProjectionRuntime<TEvents, TIdData> implements ProjectionSink {
  final Projection<TEvents, TIdData> _projection;
  final Logger _logger;
  final String
  _runtimeName; // FIXME: this should be projection name, can be accessed directory from projection
  final int _runtimeVersion;
  final RuntimeStoreProjection _runtimeStore;
  int _sequence = 0;

  late final AsyncFIFOQueue<QueueItem<TEvents, TIdData>> _queue;

  ProjectionRuntime(
    this._projection, {
    required Logger logger,
    required String runtimeName,
    required int runtimeVersion,
    required RuntimeStoreProjection runtimeStore,
  }) : _logger = logger,
       _runtimeName = runtimeName,
       _runtimeVersion = runtimeVersion,
       _runtimeStore = runtimeStore {
    _queue = AsyncFIFOQueue<QueueItem<TEvents, TIdData>>(
      (v) => _handleApply(v),
    );
  }

  String get projectionName => _projection.name;
  ProjectionFailureHandler get projectionFailureHandler =>
      _projection.failureHandler;

  bool isProjection(Projection<TEvents, TIdData> projection) {
    return identical(_projection, projection);
  }

  @override
  void enqueue(EventEnvelope eventEnvelope, {void Function()? onDone}) {
    _queue.enqueue(
      QueueItem(
        aggregateIdData: eventEnvelope.streamIdData,
        event: eventEnvelope.event,
        meta: EventMetadata(occuredAt: eventEnvelope.occuredAt),
        localSequence: eventEnvelope.localSequence,
      ),
      onDone: onDone,
    );
  }

  @override
  void enqueueApplied(AppliedEvent appliedEvent, {void Function()? onDone}) {
    final aggregateIdData = _projection.streamIdPattern.toData(
      appliedEvent.streamId,
    );
    final event = _projection.eventCodec.decode(appliedEvent.encodedEvent);
    _queue.enqueue(
      QueueItem(
        aggregateIdData: aggregateIdData,
        event: event,
        meta: EventMetadata(occuredAt: appliedEvent.occuredAt),
        localSequence: appliedEvent.localSequence,
      ),
      onDone: onDone,
    );
  }

  @override
  bool shouldProcess(StreamIdPattern streamIdPattern, String onPath) {
    if (projectionFailureHandler.hasErrored()) {
      return false;
    }

    return _projection.streamIdPattern.globs(streamIdPattern, onPath);
  }

  @override
  bool shouldProcessString(String onPath) {
    if (projectionFailureHandler.hasErrored()) {
      return false;
    }

    return _projection.streamIdPattern.globsPathOnly(onPath);
  }

  Future<void> resetProjection() async {
    try {
      _queue.reset();
      await _runtimeStore.resetProjection(_projection.name, _projection.reset);
      _sequence = 0;
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
      return;
    }
  }

  /// Will sync all projections to their latest version
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
        _projection.streamIdPattern.filter,
        _sequence,
      );

      await for (final e in reader.scan()) {
        final event = _projection.eventCodec.decode(e.encodedEvent);
        final aggregateIdData = _projection.streamIdPattern.toData(e.streamId);

        await _advance(
          e.localSequence,
          () => _projection.apply(aggregateIdData, event, e.eventMetadata),
        );
      }
    } on Exception catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
      return;
    }
  }

  Future<void> _handleApply(QueueItem<TEvents, TIdData> item) async {
    assert(!projectionFailureHandler.hasErrored(), 'must not apply on error');
    if (projectionFailureHandler.hasErrored()) {
      return;
    }

    try {
      await _advance(
        item.localSequence,
        () => _projection.apply(item.aggregateIdData, item.event, item.meta),
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
  toString() => 'ProjectionRuntime(${_projection.name})';
}

class QueueItem<TEvents, TIdData> {
  final TIdData aggregateIdData;
  final TEvents event;
  final EventMetadata meta;
  final int localSequence;

  QueueItem({
    required this.aggregateIdData,
    required this.event,
    required this.meta,
    required this.localSequence,
  });
}
