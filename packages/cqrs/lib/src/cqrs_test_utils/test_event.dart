final class TestEvent<TEvent extends Object> {
  final String actor;
  final String stream;
  final TEvent event;
  final DateTime occuredAt;

  const TestEvent({
    required this.actor,
    required this.stream,
    required this.event,
    required this.occuredAt,
  });
}
