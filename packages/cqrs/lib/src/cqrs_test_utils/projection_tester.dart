import 'package:cqrs/cqrs.dart';

class ProjectionTester<Event extends Object, StreamParams> {
  final Projection<Event, StreamParams> projection;
  final List<_ProjectionTestEvent<Event, StreamParams>> _events = [];

  ProjectionTester(this.projection);

  ProjectionTester<Event, StreamParams> withEvent(
    StreamParams streamParams,
    Event event, {
    required DateTime occuredAt,
  }) {
    _events.add(_ProjectionTestEvent(streamParams, event, occuredAt));
    return this;
  }

  /// Runs the projection with given events.
  /// The projection is reset before each run.
  /// Returns true on success, false on Exception.
  Future<bool> run() async {
    try {
      await projection.reset();

      for (var i = 0; i < _events.length; i++) {
        final event = _events[i];

        final metadata = EventMetadata(occuredAt: event.occuredAt);

        await projection.apply(event.streamParams, event.event, metadata);
      }

      return true;
    } on Exception catch (e, stackTrace) {
      projection.failureHandler.capture(e, stackTrace);
      return false;
    }
  }
}

class _ProjectionTestEvent<Event, StreamParams> {
  final StreamParams streamParams;
  final Event event;
  final DateTime occuredAt;

  const _ProjectionTestEvent(this.streamParams, this.event, this.occuredAt);
}
