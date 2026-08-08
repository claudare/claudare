import 'package:core/cqrs_test_utils.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:test/test.dart';

void main() {
  for (var factory in getEventStoreFactories()) {
    group('EventStoreProjection - ${factory.name}', () {
      late EventStoreProjection store;

      setUp(() async {
        store = await factory.create();
      });

      tearDown(() async {
        await factory.cleanup();
      });

      test('get empty global events', () async {
        final res = await store.getLocalEvents(PatternFilter.any(), 0, 10);

        expect(res.sequenceNumberCursor, isNull);
        expect(res.events.length, 0);
      });

      test('get empty last global event', () async {
        final res = await store.getLocalLastEvent(PatternFilter.any());

        expect(res.localSequence, 0);
      });
    });
  }
}
