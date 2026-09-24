final class TestEvent<TEvent extends Object> {
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;

  const TestEvent(this.streamPath, this.event, this.occuredAt);
}
