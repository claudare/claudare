import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'pubsub.dart';
import 'memory_direct_pubsub.dart';
import 'memory_broadcast_pubsub.dart';
import 'proxy_init.dart';
import 'proxy_message.dart';

final directPubsub = MemoryDirectPubSub();
final broadcastPubsub = MemoryBroadcastPubSub();

// Configure routes.
final router = Router()
  ..get('/health', _healthHandler)
  ..get('/', _actorHandler);

Response _healthHandler(Request req) {
  return Response.ok('Ok');
}

Handler _actorHandler = (Request request) {
  final ProxyInit init;
  try {
    init = ProxyInit.fromHeaders(request.headers);
  } on FormatException {
    return Response.badRequest(body: 'Invalid init');
  }

  final wsHandler = webSocketHandler((channel, protocol) {
    final thisActor = init.actor;
    final group = init.group;

    void printScoped(String msg) {
      print('[$group/$thisActor] $msg');
    }

    printScoped('Connected');

    late final Unsubscribe unsubDirect;
    try {
      unsubDirect = directPubsub.subscribe(thisActor, (message) {
        channel.sink.add(message);
      });
    } catch (_) {
      printScoped('Already subscribed');
      channel.sink.close(WebSocketStatus.policyViolation, 'Already subscribed');
      return;
    }
    final Unsubscribe unsubBroadcast = broadcastPubsub.subscribe(group, (message) {
      channel.sink.add(message);
    });

    channel.stream.listen(
      (message) {
        printScoped('Sent: $message');

        try {
          final decoded = ProxyMessage.fromJson(jsonDecode(message));

          switch (decoded) {
            case ProxyDirectMessage(:final actor, :final data):
              directPubsub.publish(
                actor,
                jsonEncode(
                  ProxyDirectMessage(actor: thisActor, data: data).toJson(),
                ),
              );
            case ProxyBroadcastMessage(:final data):
              broadcastPubsub.publish(
                group,
                jsonEncode(
                  ProxyBroadcastMessage(actor: thisActor, data: data).toJson(),
                ),
              );
          }
        } catch (error) {
          printScoped('Bad message: $error');
          channel.sink.close(
            WebSocketStatus.invalidFramePayloadData,
            'Bad message',
          );
        }
      },
      onDone: () {
        unsubDirect();
        unsubBroadcast();
        printScoped('Disconnected');
      },
      onError: (error) {
        printScoped('Error: $error');
        channel.sink.close(WebSocketStatus.internalServerError, 'Stream error');
      },
      cancelOnError: true,
    );
  });

  return wsHandler(request);
};
