import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:core/src/rpc_client/exceptions.dart';
import 'package:test/test.dart';

import 'package:core/protocol.dart';
import 'package:core/src/rpc_client/transport/http.dart';
import 'package:core/src/rpc_server/handler.dart';
import 'package:core/src/rpc_server/transport/http.dart';

import 'rpc_helpers.dart';

void main() {
  late MockRpc rpc;

  setUp(() async {
    rpc = await mockHttpHandlers(
      RpcServerTransportHttp(),
      RpcClientTransportHttp(),
      (ProtoAnyMessage req, RequestContext reqCtx) async {
        if (req.runtimeType == ProtoMessagePing) {
          return null;
        }

        if (req is ProtoMessageEventQuery) {
          return ProtoMessageEventValue([
            StoredEvent(
              // client deviceId is hardcoded to 999 for now
              EventId(Timestamp(1000), reqCtx.deviceId),
              Uint8List.fromList([req.limit]),
            ),
          ]);
        }

        if (req is ProtoMessageClockQuery) {
          throw Exception('expected error');
        }

        throw Exception('not tested yet');
      },
    );
  });

  tearDown(() async {
    await rpc.close();
  });

  group('rpc', () {
    test('ping', () async {
      await rpc.client.ping();
    });

    test('data stuff (temporary)', () async {
      final response = await rpc.client.queryEvents(
        ProtoMessageEventQuery(
          EventVectorClockRange.fromStart(EventVectorClock.empty()),
          42,
        ),
      );

      expect(response.events.length, equals(1));
      expect(
        response.events.first.id.deviceId,
        equals(DeviceId(999)), // hardcoded
      );
      expect(response.events.first.bytes[0], equals(42));
    });

    test('errors', () async {
      expect(
        () => rpc.client.queryClock(),
        throwsA(
          predicate(
            (x) => x is RpcException && x.toString().contains('expected error'),
          ),
        ),
      );
    });
  });
}
