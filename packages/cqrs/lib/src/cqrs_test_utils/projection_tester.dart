import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

/// Loads one model and applies events and deletions to a [Projection] in order.
class ProjectionTester<TModel extends Object, TEvent extends Object> {
  final Projection<TModel, TEvent> projection;
  final List<Object> _testEvents = [];
  late final Future<ProjectionLoad<TModel>> _loaded = Future.sync(
    projection.load,
  );
  int _nextEventIndex = 0;

  ProjectionTester(this.projection);

  ProjectionTester<TModel, TEvent> withEvent(
    String streamPath,
    TEvent event, {
    String actor = 'a',
    required DateTime occuredAt,
  }) {
    _testEvents.add(
      TestEvent(
        actor: actor,
        stream: streamPath,
        event: event,
        occuredAt: occuredAt,
      ),
    );
    return this;
  }

  /// Adds a stream deletion at the next log position.
  ProjectionTester<TModel, TEvent> withStreamDeleted(
    String streamPath, {
    String actor = 'a',
    required DateTime occuredAt,
  }) {
    _testEvents.add(
      StreamDeletion(
        actor: actor,
        streamPath: streamPath,
        occuredAt: occuredAt,
        logPosition: _testEvents.length,
      ),
    );
    return this;
  }

  Future<TModel> run() async {
    final model = (await _loaded).model;
    for (var i = _nextEventIndex; i < _testEvents.length; i++) {
      final entry = _testEvents[i];
      if (entry is StreamDeletion) {
        if (projection.filter.doesMatchPath(entry.streamPath)) {
          await projection.onStreamDeleted(model, entry);
        }
        _nextEventIndex = i + 1;
        continue;
      }
      final event = entry as TestEvent<TEvent>;
      if (!projection.filter.doesMatchPath(event.stream)) {
        _nextEventIndex = i + 1;
        continue;
      }

      final envelope = EventEnvelope<TEvent>(
        actor: event.actor,
        streamPath: event.stream,
        event: event.event,
        occuredAt: event.occuredAt,
        logPosition: i,
      );
      await projection.apply(model, envelope);
      _nextEventIndex = i + 1;
    }
    return model;
  }
}
