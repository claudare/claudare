import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:test/test.dart';

typedef EventStoreFactory = Future<EventStoreProjection> Function();

void main() {
  final implementations = <String, EventStoreFactory>{
    'InMemory': () async {
      final s = MemoryEventStore(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      return s;
    },
    // 'SQL': () async {
    //   final s = await createSqlEventStore();
    //   return s;
    // },
  };

  implementations.forEach((name, factory) {
    group('EventStoreProjection - $name', () {
      late EventStoreProjection store;

      setUp(() async {
        store = await factory();
      });

      tearDown(() async {
        // TODOs
      });

      test("get empty global events", () async {
        final res = await store.getGlobalEvents(0, [], 10);

        expect(res.sequenceNumberCursor, equals(null));
        expect(res.events.length, equals(0));
      });
    });
  });
}
