import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'pubsub.dart';
import 'protocol.dart';

final pubsub = MemoryPubSub();

// Configure routes.
final _router = Router()
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

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Proxy server listening on port ${server.port}');
}
