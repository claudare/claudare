import 'dart:async';

import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

typedef ProjectionApply<TEvent extends Object, TParams> =
    FutureOr<void> Function(
      TParams streamParams,
      TEvent event,
      EventMetadata metadata,
    );

final class ProjectionRoute<TEvent extends Object, TParams> {
  final StreamRoute<TParams> streamRoute;
  final ProjectionApply<TEvent, TParams> _apply;

  const ProjectionRoute({
    required this.streamRoute,
    required ProjectionApply<TEvent, TParams> apply,
  }) : _apply = apply;

  bool matches(String streamPath, Object event) =>
      streamRoute.matches(streamPath) && event is TEvent;

  Future<void> apply(
    String streamPath,
    Object event,
    EventMetadata metadata,
  ) async {
    if (!streamRoute.matches(streamPath)) {
      throw ProjectionRouteException(
        'Projection route ${streamRoute.pattern} does not match $streamPath',
      );
    }
    if (event is! TEvent) {
      throw ProjectionRouteException(
        'Projection route expected $TEvent, but received ${event.runtimeType}',
      );
    }

    final streamParams = streamRoute.parseParams(streamPath);
    await _apply(streamParams, event, metadata);
  }
}

final class ProjectionRouteException implements Exception {
  final String message;

  const ProjectionRouteException(this.message);

  @override
  String toString() => 'ProjectionRouteException: $message';
}
