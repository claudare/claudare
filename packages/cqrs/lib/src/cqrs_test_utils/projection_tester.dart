import 'package:cqrs/cqrs.dart';

class ProjectionTester {
  final Projection projection;
  final List<ProjectionRoute> _routes;
  final List<_ProjectionTestEvent> _events = [];

  ProjectionTester(this.projection)
    : _routes = List.unmodifiable(projection.routes);

  ProjectionTester withEvent(
    String streamPath,
    Object event, {
    required DateTime occuredAt,
  }) {
    _events.add(_ProjectionTestEvent(streamPath, event, occuredAt));
    return this;
  }

  Future<bool> run() async {
    try {
      await projection.reset();
      var applied = false;

      for (final event in _events) {
        final metadata = EventMetadata(occuredAt: event.occuredAt);
        for (final route in _routes) {
          if (route.matches(event.streamPath, event.event)) {
            await route.apply(event.streamPath, event.event, metadata);
            applied = true;
          }
        }
      }

      if (applied) {
        projection.onBatchApplied();
      }
      return true;
    } on Exception catch (error, stackTrace) {
      projection.failureHandler.capture(error, stackTrace);
      return false;
    }
  }
}

final class _ProjectionTestEvent {
  final String streamPath;
  final Object event;
  final DateTime occuredAt;

  const _ProjectionTestEvent(this.streamPath, this.event, this.occuredAt);
}
