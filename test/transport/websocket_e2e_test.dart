import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../transport_helpers.dart';

// TODO: this needs error testing
void main() {
  group('Websocket Transport', () {
    late TestServerClientTransport transports;
    setUp(() async {
      transports = await TestServerClientTransport.websockets();
    });
    tearDown(() async {
      await transports.serverTransport.stop();
      // await transports.stop();
    });

    test('works end-to-end', () async {
      int clientCount = 0;
      int serverCount = 0;

      final completer = Completer<void>();

      // client pings back
      transports.clientConnection.stream.listen((data) async {
        if (clientCount < 3) {
          transports.clientConnection.sink.add(data);
          clientCount++;
        } else {
          await transports.clientConnection.disconnect();
          completer.complete();
        }
      });
      // server ping back
      transports.serverConnection.stream.listen((data) {
        if (serverCount < 3) {
          transports.serverConnection.sink.add(data);
          serverCount++;
        }
      });

      transports.serverConnection.sink.add(Uint8List(1));

      await completer.future;

      expect(clientCount, equals(3));
      expect(serverCount, equals(3));
    });
  }, tags: ["e2e"]);
}
