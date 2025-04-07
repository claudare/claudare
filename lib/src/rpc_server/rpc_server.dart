import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/protocol.dart';
import 'package:core/src/rpc_server/handler.dart';
import 'package:core/src/rpc_server/transport.dart';

typedef ServerHandlerFn =
    Future<ProtoAnyMessage?> Function(
      ProtoAnyMessage req,
      RequestContext reqCtx,
    );

class RpcServer {
  final RpcServerTransport transport;
  final ServerHandlerFn serverHandler;

  const RpcServer(this.transport, this.serverHandler);

  // int get serverPort => transport.port;

  Future<void> start(Uri listtenUri) async {
    await transport.start(listtenUri, _handler);
  }

  Future<void> stop() async {
    await transport.stop();
  }

  Future<Uint8List> _handler(Uint8List rawReq) async {
    final requestPayload = ProtoPayload.unpack(rawReq);
    final handled = await handlePayload(requestPayload);

    if (handled == null) {
      return Uint8List(0);
    }

    final response = handled.pack();
    return response;
  }

  /// given the request, returns a response...
  /// but this needs access to some sort of context like EventStore and BlobStore
  /// Also, this will throw on errors, and it must be routed accordingly
  Future<ProtoPayload?> handlePayload(ProtoPayload req) async {
    // TODO: server auth
    final thisServerDeviceId = DeviceId(10000);

    final auth = req.getAuth();
    final ack = req.getAck();

    final reqCtx = RequestContext(auth.deviceId);

    try {
      final resData = await serverHandler(req.data, reqCtx);

      if (ack == null) {
        return null;
      }

      final res = ProtoPayload({}, resData ?? ProtoMessageEmpty());

      res.setHeader(ProtoHeaderAuth(thisServerDeviceId));
      res.setHeader(ProtoHeaderAck(ack.payloadId, ""));

      return res;
    } catch (e, stackTrace) {
      print('request error $e; $stackTrace');

      if (ack == null) {
        return null;
      }

      // for now always send full errors back
      return ProtoPayload.errorResponse(
        ack,
        '$e; $stackTrace',
        auth: ProtoHeaderAuth(thisServerDeviceId),
      );
    }
  }
}
