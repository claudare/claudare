import 'package:cqrs/cqrs.dart';

class ProjectionTester<TEvent extends Object, TParams> {
  final Projection<TEvent, TParams> projection;
  final List<_ProjectionTestEvent<TEvent>> _events = [];

  ProjectionTester(this.projection);

  ProjectionTester<TEvent, TParams> withEvent(
    String streamPath,
    TEvent event, {
    required DateTime occuredAt,
  }) {
    _events.add(_ProjectionTestEvent(streamPath, event, occuredAt));
    return this;
  }

  Future<bool> run() async {
    try {
      await projection.reset();

      for (final event in _events) {
        final streamParams = projection.streamRoute.parseParams(
          event.streamPath,
        );
        await projection.apply(
          streamParams,
          event.event,
          EventMetadata(occuredAt: event.occuredAt),
        );
      }

      if (_events.isNotEmpty) {
        projection.onBatchApplied();
      }
      return true;
    } on Exception catch (error, stackTrace) {
      projection.failureHandler.capture(error, stackTrace);
      return false;
    }
  }
}

final class _ProjectionTestEvent<TEvent extends Object> {
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;

  const _ProjectionTestEvent(this.streamPath, this.event, this.occuredAt);
}
