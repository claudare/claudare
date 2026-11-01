import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:proxy/proxy.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:transport_proxy/transport_proxy.dart';

void main() {
  late Uri baseUrl;

  setUp(() async {
    final server = await shelf_io.serve(
      createRouter(logger: const NoopLogger()).call,
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = Uri.parse('ws://127.0.0.1:${server.port}/');
    addTearDown(() => server.close(force: true));
  });

  test('direct messages reach the addressed actor', () async {
    final sender = await _ProxyClient.connect(baseUrl, 'sender', 'group');
    final receiver = await _ProxyClient.connect(baseUrl, 'receiver', 'group');

    sender.send(
      const ProxyMessage(
        type: ProxyMessageType.direct,
        actor: 'receiver',
        data: 'direct payload',
      ),
    );

    final received = await receiver.receive();
    expect(received.type, ProxyMessageType.direct);
    expect(received.data, 'direct payload');
  });

  test('broadcast messages reach all actors in the sender group', () async {
    final sender = await _ProxyClient.connect(baseUrl, 'sender', 'group');
    final receiver = await _ProxyClient.connect(baseUrl, 'receiver', 'group');

    sender.send(
      const ProxyMessage(
        type: ProxyMessageType.broadcast,
        actor: 'ignored',
        data: 'broadcast payload',
      ),
    );

    for (final client in [sender, receiver]) {
      final received = await client.receive();
      expect(received.type, ProxyMessageType.broadcast);
      expect(received.data, 'broadcast payload');
    }
  });

  for (final type in ProxyMessageType.values) {
    test('${type.name} messages do not reach actors in other groups', () async {
      final sender = await _ProxyClient.connect(baseUrl, 'sender', 'first');
      final outsider = await _ProxyClient.connect(
        baseUrl,
        'outsider',
        'second',
      );

      sender.send(
        ProxyMessage(type: type, actor: 'outsider', data: 'isolated'),
      );
      if (type == ProxyMessageType.broadcast) {
        await sender.receive();
      }
      // Wait for the server to process the preceding message.
      sender.send(
        const ProxyMessage(
          type: ProxyMessageType.direct,
          actor: 'sender',
          data: 'processed',
        ),
      );
      expect((await sender.receive()).data, 'processed');

      // Any leaked message would arrive before this same-group marker.
      outsider.send(
        const ProxyMessage(
          type: ProxyMessageType.direct,
          actor: 'outsider',
          data: 'marker',
        ),
      );
      expect((await outsider.receive()).data, 'marker');
    });

    test('${type.name} messages identify the connected sender', () async {
      final sender = await _ProxyClient.connect(baseUrl, 'sender', 'group');
      final receiver = await _ProxyClient.connect(baseUrl, 'receiver', 'group');

      sender.send(ProxyMessage(type: type, actor: 'receiver', data: 'payload'));

      final received = await receiver.receive();
      expect(received.actor, 'sender');
    });
  }

  test(
    'direct routing distinguishes identical actors in separate groups',
    () async {
      final first = await _ProxyClient.connect(baseUrl, 'receiver', 'first');
      final second = await _ProxyClient.connect(baseUrl, 'receiver', 'second');

      first.send(
        const ProxyMessage(
          type: ProxyMessageType.direct,
          actor: 'receiver',
          data: 'first payload',
        ),
      );
      second.send(
        const ProxyMessage(
          type: ProxyMessageType.direct,
          actor: 'receiver',
          data: 'second payload',
        ),
      );

      expect((await first.receive()).data, 'first payload');
      expect((await second.receive()).data, 'second payload');
    },
  );
}

class _ProxyClient {
  final WebSocket _socket;
  final StreamIterator<dynamic> _messages;

  _ProxyClient(this._socket) : _messages = StreamIterator(_socket);

  static Future<_ProxyClient> connect(
    Uri baseUrl,
    String actor,
    String group,
  ) async {
    final socket = await WebSocket.connect(
      baseUrl.toString(),
      headers: ProxyInit(actor: actor, group: group).toHeaders(),
    );
    final client = _ProxyClient(socket);
    addTearDown(() async {
      await socket.close();
      await client._messages.cancel();
    });
    return client;
  }

  void send(ProxyMessage message) {
    _socket.add(jsonEncode(message.toJson()));
  }

  Future<ProxyMessage> receive() async {
    final hasMessage = await _messages.moveNext().timeout(
      const Duration(seconds: 5),
    );
    if (!hasMessage) {
      throw StateError('Proxy connection closed before receiving a message');
    }
    return ProxyMessage.fromJson(
      jsonDecode(_messages.current as String) as Map<String, dynamic>,
    );
  }
}
