import 'package:cqrs/cqrs.dart';

class ProjectionTester<Event, StreamIdData> {
  final Projection<Event, StreamIdData> projection;
  final List<_ProjectionTestEvent<Event, StreamIdData>> _events = [];

  ProjectionTester(this.projection);

  ProjectionTester<Event, StreamIdData> withEvent(
    StreamIdData streamIdData,
    Event event, {
    DateTime? occuredAt,
  }) {
    _events.add(_ProjectionTestEvent(streamIdData, event, occuredAt));
    return this;
  }

  void assertEventOccuredAt() {
    var defined = 0;
    var undefined = 0;

    for (var event in _events) {
      if (event.occuredAt == null) {
        undefined++;
      } else {
        defined++;
      }
    }

    if (defined > 0 && undefined > 0) {
      throw StateError(
        'Some events have an occuredAt timestamp and some do not. Either define all occuredAt timestamps, or define none.',
      );
    }
  }

  /// Runs the projection with given events.
  /// The sequence starts at 1!
  /// If no occuredAt timestamps are defined, they are automatically generated,
  /// starting at zero unix timestamp and increasing by 1 second for each event emitted.
  /// This function return true on sucess and false on failure.
  /// For additional failure context check [failureState].
  Future<bool> run() async {
    assertEventOccuredAt();

    try {
      final checkpoint = await projection.checkpoint();
      if (!checkpoint.isProjectionInitialized) {
        await projection.reset();
      }

      if (checkpoint.localSequence > _events.length) {
        // TODO: check this is accurate?
        throw ArgumentError(
          'Checkpoint local sequence is greater than the number of events',
        );
      }

      for (var i = checkpoint.localSequence; i < _events.length; i++) {
        final event = _events[i];

        final metadata = EventMetadata(
          localSequence: i + 1,
          occuredAt:
              event.occuredAt ??
              DateTime.fromMillisecondsSinceEpoch(i * 1000, isUtc: true),
        );

        await projection.apply(event.streamIdData, event.event, metadata);
      }

      return true;
    } catch (e, stackTrace) {
      projection.failureHandler.capture(e, stackTrace);
      return false;
    }
  }
}

class _ProjectionTestEvent<Event, StreamIdData> {
  final StreamIdData streamIdData;
  final Event event;
  final DateTime? occuredAt;

  const _ProjectionTestEvent(this.streamIdData, this.event, this.occuredAt);
}
