import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'pubsub.dart';
import 'protocol.dart';

final pubsub = MemoryPubSub();

// Configure routes.
final router = Router()
  ..get('/', _healthHandler)
  ..get('/health', _healthHandler)
  ..get('/<actor>', _actorHandler);

Response _healthHandler(Request req) {
  return Response.ok('Ok');
}

Handler _actorHandler = (Request request) {
  final segments = request.url.pathSegments;
  if (segments.length != 1 || segments.first.isEmpty) {
    return Response.notFound('Invalid path');
  }

  final thisActor = segments.first;

  final wsHandler = webSocketHandler((channel, protocol) {
    print('[$thisActor] connected');

    final unsub = pubsub.subscribe(thisActor, (message) {
      channel.sink.add(message);
    });
    if (unsub == null) {
      print('[$thisActor] Already subscribed');
      channel.sink.close(WebSocketStatus.policyViolation, 'Already subscribed');
      return;
    }
    channel.stream.listen(
      (message) {
        print('[$thisActor] sent: $message');

        try {
          final decoded = ProxyMessage.fromJson(jsonDecode(message));

          pubsub.publish(
            decoded.actor,
            jsonEncode(
              ProxyMessage(actor: thisActor, data: decoded.data).toJson(),
            ),
          );
        } catch (error) {
          print('[$thisActor] bad request: $error');
          channel.sink.close(
            WebSocketStatus.invalidFramePayloadData,
            'Bad request',
          );
        }
      },
      onDone: () {
        unsub();
        print('[$thisActor] disconnected');
      },
      onError: (error) {
        print('[$thisActor] error: $error');
        channel.sink.close(WebSocketStatus.internalServerError, 'Stream error');
      },
      cancelOnError: true,
    );
  });

  return wsHandler(request);
};
