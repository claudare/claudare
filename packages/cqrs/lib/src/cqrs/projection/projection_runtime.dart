import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/event_store/global_event_reader.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/projection/projection_sink.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:queue/queue.dart';

import 'projection_failure_handler.dart';

class ProjectionRuntime<TEvents, TIdData> implements ProjectionSink {
  final Projection<TEvents, TIdData> _projection;
  final int _pageSize;
  final Logger _logger;
  final String _runtimeName;
  final int _runtimeVersion;

  late final AsyncFIFOQueue<QueueItem<TEvents, TIdData>> _queue;

  ProjectionRuntime(
    this._projection,
    this._pageSize, {
    required Logger logger,
    required String runtimeName,
    required int runtimeVersion,
  }) : _logger = logger,
       _runtimeName = runtimeName,
       _runtimeVersion = runtimeVersion {
    _queue = AsyncFIFOQueue<QueueItem<TEvents, TIdData>>(
      (v) => _handleApply(v),
    );
  }

  String get projectionName => _projection.name;
  ProjectionFailureHandler get projectionFailureHandler =>
      _projection.failureHandler;

  // ProjectionFailureState get exceptionHandler => _failureState;

  bool isProjection(Projection<TEvents, TIdData> projection) {
    return identical(_projection, projection);
  }

  @override
  void enqueue(EventEnvelope eventEnvelope, {void Function()? onDone}) {
    _queue.enqueue(
      QueueItem(
        aggregateIdData: eventEnvelope.streamIdData,
        event: eventEnvelope.event,
        meta: eventEnvelope.metadata,
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

  Future<void> resetProjection() async {
    try {
      _queue.reset();
      await _projection.reset();
    } catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
      return;
    }
  }

  /// Will sync all projections to their latest version
  Future<void> catchupSelfLoad(EventStoreProjection eventStore) async {
    if (projectionFailureHandler.hasErrored()) {
      return;
    }

    try {
      final checkpoint = await _projection.checkpoint();

      if (!checkpoint.isProjectionInitialized) {
        // make sure when tables are created and ready to return zero value instead of null.
        _logger.warning(
          'runtime $_runtimeName@$_runtimeVersion: projection ${_projection.name} '
          'was not initialized during catch-up; resetting it',
        );
        await _projection.reset();
      }

      final reader = GlobalEventReader(
        eventStore,
        _projection.streamIdPattern.filter,
        _pageSize,
        checkpoint.localSequence,
      );

      // paginate
      while (await reader.loadMore()) {
        StoredEventProjectionRead? e;
        while ((e = reader.next()) != null) {
          final event = _projection.eventCodec.decode(e!.encodedEvent);

          final aggregateIdData = _projection.streamIdPattern.toData(
            e.streamId,
          );

          await _projection.apply(aggregateIdData, event, e.eventMetadata);
        }
      }
    } catch (error, stackTrace) {
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
      await _projection.apply(item.aggregateIdData, item.event, item.meta);
    } catch (error, stackTrace) {
      projectionFailureHandler.capture(error, stackTrace);
    }
  }

  @override
  toString() => 'ProjectionRuntime(${_projection.name})';
}

class QueueItem<TEvents, TIdData> {
  TIdData aggregateIdData;
  TEvents event;
  EventMetadata meta;

  QueueItem({
    required this.aggregateIdData,
    required this.event,
    required this.meta,
  });
}
