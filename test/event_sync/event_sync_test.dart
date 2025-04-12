import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:core/protocol.dart';
import 'package:core/src/client_transport/connection/stub.dart';
import 'package:core/src/event_store/event_clock.dart';
import 'package:core/src/event_sync/event_sync.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import '../keychain_helpers.dart';

// class MockNetConnection extends Mock implements NetConnection {}

class MockEventSyncContext extends Mock implements EventSyncContext {}

void main() {
  group('EventSync', () {
    final clientDeviceId = DeviceId(0);
    final serverDeviceId = DeviceId(1000);
    final syncedEventClock = EventVectorClock({
      clientDeviceId: EventClock(Timestamp(1000), 1),
    });

    late NetConnectionStub connection;
    late MockEventSyncContext context;
    late EventSync eventSync;

    final keychainPairs = TestKeychainPairs.fromIds(
      serverDeviceId,
      clientDeviceId,
    );

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      connection = NetConnectionStub();
      context = MockEventSyncContext();

      eventSync = EventSync(
        context,
        connection,
        isClient: true,
        deviceKeychain: keychainPairs.client,
        peerDeviceId: serverDeviceId,
        localVC: syncedEventClock,
      );
    });
    tearDown(() async {
      await connection.disconnect();
    });

    test('correct auth and clock exchange', () async {
      // ack successfully
      connection.onPayload((payload) {
        if (payload.data is! ProtoMessageAck) {
          connection.addPayloadMessage(ProtoMessageAck(payload.id));
        }
      });

      final serverClaim = await keychainPairs.server.makeClaim(clientDeviceId);
      expect(eventSync.authExchange.done, isFalse);

      expectLater(eventSync.start(), completes);

      // send own auth
      connection.addPayloadMessage(ProtoMessageAuth(serverClaim));

      await Future.delayed(Duration(milliseconds: 100));

      expect(eventSync.authExchange.done, isTrue);

      // check that we sent 3 messages: 1 auth and 2 acks
      expect(connection.ingresValuesPayload, hasLength(3));
      // the peer sent 3: 1 auth, 1 ack, 1 clock
      expect(connection.exgresValuesPayload, hasLength(3));
      expect(
        connection.exgresValuesPayload.last.data,
        isA<ProtoMessageClockValue>(),
      );

      connection.addPayloadMessage(ProtoMessageClockValue(syncedEventClock));

      await Future.delayed(Duration(milliseconds: 100));

      expect(eventSync.clockExchange.done, isTrue);

      // We sent 4 messages: 1 auth, 2 acks, 1 clock
      expect(connection.ingresValuesPayload, hasLength(4));
      // the peer sent 4: 1 auth, 1 ack, 1 clock, 1 ack
      expect(connection.exgresValuesPayload, hasLength(4));

      // client should be reponsive to pings
      connection.addPayloadMessage(ProtoMessagePing());

      await Future.delayed(Duration(milliseconds: 100));

      // 1 auth, 1 ack, 1 clock, 1 ack, 1 ack
      expect(connection.exgresValuesPayload, hasLength(5));
      expect(connection.exgresValuesPayload.last.data, isA<ProtoMessageAck>());

      // print(connection.ingresValuesPayload);
      // print(connection.exgresValuesPayload);
    });
  });
}
