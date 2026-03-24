import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_memory.dart';
import 'package:test/test.dart';

typedef EventStoreFactory = Future<EventStoreCommand> Function();

void main() {
  final implementations = <String, EventStoreFactory>{
    'InMemory': () async {
      final s = EventStoreMemory(
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
    group('EventStore - $name', () {
      late EventStoreCommand store;

      setUp(() async {
        store = await factory();
      });

      tearDown(() async {
        // TODOs
      });

      test("get empty stream events", () async {
        final res = await store.getStreamEventsCursor("non-existing", 10, null);

        expect(res.originatingVersion, equals(0));
        expect(res.versionCursor, equals(null));
        expect(res.events.length, equals(0));
      });

      test("get empty stream info (minimal)", () async {
        final res = await store.getStreamMinimal("non-existing");

        expect(res.totalCount, equals(0));
      });
    });
  });
}
