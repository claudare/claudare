import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/services.dart';

// test the services singleton, make sure it can be tested across the app
void main() {
  group('Services', () {
    // late Services services;

    setUp(() async {
      await Services().repo.initFromEvents([
        (
          EventId(Timestamp(1000), DeviceId(0)),
          NoteCreated(
            GenericId('note', Timestamp(1000), Counter16(0), DeviceId(0)),
          ),
        ),
        (
          EventId(Timestamp(2000), DeviceId(0)),
          NoteCreated(
            GenericId('note', Timestamp(2000), Counter16(1), DeviceId(0)),
          ),
        ),
      ]);
    });

    test('concurrent access is okay run 1', () async {
      final repo = Services().repo;
      expect(repo.order.items.length, equals(2));
      await Future.delayed(Duration(milliseconds: 100));
      await repo.submitEvent(NoteCreated(repo.newGenericId('')));
      //sleep for a bit
      await Future.delayed(Duration(milliseconds: 100));

      expect(repo.order.items.length, equals(3));
    });

    test('concurrent access is okay run 2', () async {
      final repo = Services().repo;
      expect(repo.order.items.length, equals(2));
      await Future.delayed(Duration(milliseconds: 100));
      await repo.submitEvent(NoteCreated(repo.newGenericId('')));
      //sleep for a bit
      await Future.delayed(Duration(milliseconds: 100));

      expect(repo.order.items.length, equals(3));
    });
  });
}
