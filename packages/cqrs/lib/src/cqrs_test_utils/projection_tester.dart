import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

/// Loads one model and applies supplied events to a [Projection] in order.
class ProjectionTester<TModel extends Object, TEvent extends Object> {
  final Projection<TModel, TEvent> projection;
  final List<TestEvent<TEvent>> _testEvents = [];
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

  Future<TModel> run() async {
    final model = (await _loaded).model;
    for (var i = _nextEventIndex; i < _testEvents.length; i++) {
      final event = _testEvents[i];
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
