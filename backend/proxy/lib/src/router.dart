import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:transport_proxy/transport_proxy.dart';

import 'pubsub.dart';
import 'memory_direct_pubsub.dart';
import 'memory_broadcast_pubsub.dart';

final directPubsub = MemoryDirectPubSub();
final broadcastPubsub = MemoryBroadcastPubSub();

Router createRouter({required Logger logger}) => Router()
  ..get('/health', _healthHandler)
  ..get('/', (Request request) => _actorHandler(request, logger));

Response _healthHandler(Request req) {
  return Response.ok('Ok');
}

FutureOr<Response> _actorHandler(Request request, Logger logger) {
  final ProxyInit init;
  try {
    init = ProxyInit.fromHeaders(request.headers);
  } on FormatException {
    return Response.badRequest(body: 'Invalid init');
  }

  final wsHandler = webSocketHandler((channel, protocol) {
    final thisActor = init.actor;
    final group = init.group;

    final scope = '[$group/$thisActor]';
    logger.info('$scope Connected');

    late final Unsubscribe unsubDirect;
    try {
      unsubDirect = directPubsub.subscribe(
        _encodePubsubTarget(group, thisActor),
        (message) {
          channel.sink.add(message);
        },
      );
    } catch (_) {
      logger.warning('$scope Already subscribed');
      channel.sink.close(WebSocketStatus.policyViolation, 'Already subscribed');
      return;
    }
    final Unsubscribe unsubBroadcast = broadcastPubsub.subscribe(group, (
      message,
    ) {
      channel.sink.add(message);
    });

    channel.stream.listen(
      (message) {
        logger.debug('$scope Sent: $message');

        try {
          final decoded = ProxyMessage.fromJson(jsonDecode(message));

          switch (decoded.type) {
            case ProxyMessageType.direct:
              directPubsub.publish(
                _encodePubsubTarget(group, decoded.actor),
                jsonEncode(
                  ProxyMessage(
                    type: decoded.type,
                    actor: thisActor,
                    data: decoded.data,
                  ).toJson(),
                ),
              );
            case ProxyMessageType.broadcast:
              broadcastPubsub.publish(
                group,
                jsonEncode(
                  ProxyMessage(
                    type: decoded.type,
                    actor: thisActor,
                    data: decoded.data,
                  ).toJson(),
                ),
              );
          }
        } catch (error, stackTrace) {
          logger.warning('$scope Bad message');
          logger.debug('$scope Bad message details', error, stackTrace);
          channel.sink.close(
            WebSocketStatus.invalidFramePayloadData,
            'Bad message',
          );
        }
      },
      onDone: () {
        unsubDirect();
        unsubBroadcast();
        logger.info('$scope Disconnected');
      },
      onError: (error) {
        logger.error('$scope Stream error', error);
        channel.sink.close(WebSocketStatus.internalServerError, 'Stream error');
      },
      cancelOnError: true,
    );
  });

  return wsHandler(request);
}

String _encodePubsubTarget(String group, String actor) => '$group/$actor';
