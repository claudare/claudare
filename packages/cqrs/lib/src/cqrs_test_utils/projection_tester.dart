import 'package:cqrs/cqrs.dart';

class ProjectionTester<Event, StreamIdData> {
  final Projection<Event, StreamIdData> projection;
  final List<_ProjectionTestEvent<Event, StreamIdData>> _events = [];

  ProjectionTester(this.projection);

  ProjectionTester<Event, StreamIdData> withEvent(
    StreamIdData streamIdData,
    Event event, {
    required DateTime occuredAt,
  }) {
    _events.add(_ProjectionTestEvent(streamIdData, event, occuredAt));
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

        await projection.apply(event.streamIdData, event.event, metadata);
      }

      return true;
    } on Exception catch (e, stackTrace) {
      projection.failureHandler.capture(e, stackTrace);
      return false;
    }
  }
}

class _ProjectionTestEvent<Event, StreamIdData> {
  final StreamIdData streamIdData;
  final Event event;
  final DateTime occuredAt;

  const _ProjectionTestEvent(this.streamIdData, this.event, this.occuredAt);
}
