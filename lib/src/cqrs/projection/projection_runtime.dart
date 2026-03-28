import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/event_store/global_event_reader.dart';
import 'package:core/src/cqrs/projection/projection.dart';
import 'package:core/src/cqrs/projection/projection_failure_state.dart';
import 'package:core/src/cqrs/projection/projection_sink.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:core/src/utils/async_fifo_queue.dart';

class ProjectionRuntime<TEvents, TIdData> implements ProjectionSink {
  final Projection<TEvents, TIdData> _projection;
  final ProjectionFailureState _failureState;
  final int _pageSize;

  late final AsyncFIFOQueue<QueueItem<TEvents, TIdData>> _queue;

  ProjectionRuntime(this._projection, this._failureState, this._pageSize) {
    _queue = AsyncFIFOQueue<QueueItem<TEvents, TIdData>>(
      (v) => _handleApply(v),
    );
  }

  ProjectionFailureState get exceptionHandler => _failureState;

  bool isProjection(Projection<TEvents, TIdData> projection) {
    return identical(_projection, projection);
  }

  @override
  void enqueue(LiveEventFull liveEvent, {void Function()? onDone}) {
    _queue.enqueue(
      QueueItem(
        aggregateIdData: liveEvent.streamIdData,
        event: liveEvent.event,
        meta: liveEvent.eventMetadata,
      ),
      liveEvent.localSequence,
      onDone: onDone,
    );
  }

  @override
  bool shouldProcess(StreamIdPattern streamIdPattern, String onPath) {
    if (_failureState.hasError) {
      return false;
    }

    return _projection.streamIdPattern.globs(streamIdPattern, onPath);
  }

  Future<void> catchupSelfLoad(EventStoreProjection eventStore) async {
    try {
      final checkpoint = await _projection.checkpoint();

      if (checkpoint.isZero) {
        await _projection.reset();
      }

      final reader = GlobalEventReader(
        eventStore,
        _pageSize,
        _projection.streamIdPattern.filter,
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
      _failureState.capture(error, stackTrace);
      return;
    }
  }

  Future<void> _handleApply(QueueItem<TEvents, TIdData> item) async {
    assert(!_failureState.hasError, "must not apply on error");
    if (_failureState.hasError) {
      return;
    }

    try {
      await _projection.apply(item.aggregateIdData, item.event, item.meta);
    } catch (error, stackTrace) {
      _failureState.capture(error, stackTrace);
    }
  }
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
