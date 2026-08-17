import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/exception/event_codec_exception.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';

final class DecodedLocalEvent {
  final LocalEvent durableEvent;
  final Object event;

  const DecodedLocalEvent({required this.durableEvent, required this.event});
}

abstract interface class PreparedProjectionPageAdapter {
  int get position;

  Future<void> applyPage(List<DecodedLocalEvent> page);
}

final class ProjectionPageAdapter<TEvent extends Object, TParams>
    implements PreparedProjectionPageAdapter {
  final Projection<TEvent, TParams> _projection;
  final RuntimeStoreProjection _runtimeStore;

  @override
  int position;

  ProjectionPageAdapter({
    required Projection<TEvent, TParams> projection,
    required this.position,
    required RuntimeStoreProjection runtimeStore,
  }) : _projection = projection,
       _runtimeStore = runtimeStore {
    RangeError.checkNotNegative(position, 'position');
  }

  @override
  Future<void> applyPage(List<DecodedLocalEvent> page) async {
    if (page.isEmpty) return;

    final pageEnd = page.last.durableEvent.localSequence;
    if (pageEnd <= position) return;

    var hadMatches = false;
    await _runtimeStore.advanceProjection(
      _projection.name,
      position,
      pageEnd,
      () async {
        for (final decoded in page) {
          final durableEvent = decoded.durableEvent;
          if (durableEvent.localSequence <= position ||
              !_projection.streamRoute.matches(durableEvent.streamPath)) {
            continue;
          }

          final event = decoded.event;
          if (event is! TEvent) {
            throw EventCodecException(
              'Event kind ${durableEvent.encodedEvent.kind} decoded to '
              '${event.runtimeType}, but $TEvent was expected',
              direction: EventCodecDirection.decode,
              kind: durableEvent.encodedEvent.kind,
            );
          }

          hadMatches = true;
          await _projection.apply(
            _projection.streamRoute.parseParams(durableEvent.streamPath),
            event,
            durableEvent.eventMetadata,
          );
        }
      },
    );
    position = pageEnd;

    if (hadMatches) _projection.onBatchApplied();
  }
}
