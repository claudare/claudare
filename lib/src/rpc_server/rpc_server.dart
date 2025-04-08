import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/device_keychain.dart';
import 'package:core/protocol.dart';
import 'package:core/src/rpc_client/exceptions.dart';
import 'package:core/src/rpc_server/handler.dart';
import 'package:core/src/rpc_server/transport.dart';

typedef ServerHandlerFn =
    Future<ProtoAnyMessage?> Function(
      ProtoAnyMessage req,
      RequestContext reqCtx,
    );

class RpcServer {
  final RpcServerTransport _transport;
  final DeviceKeychain _deviceKeychain;
  final ServerHandlerFn _serverHandler;

  const RpcServer(this._transport, this._deviceKeychain, this._serverHandler);

  // int get serverPort => transport.port;

  Future<void> start(Uri listtenUri) async {
    await _transport.start(listtenUri, _handler);
  }

  Future<void> stop() async {
    await _transport.stop();
  }

  // serialization errors are sent as unstructured insside the transport...
  // not very streamlined, but okay for now.
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
    DeviceId senderId;
    DeviceClaim resClaim;

    try {
      // validate the auth. these throw when something is not right
      final auth = req.getAuth();
      final device = await _deviceKeychain.checkClaim(auth.claim);
      senderId = device.deviceId;
      resClaim = await _deviceKeychain.makeClaim(senderId);
    } catch (e) {
      throw RpcException('Auth failed: $e');
    }

    final ack = req.getAck();
    final reqCtx = RequestContext(senderId);

    try {
      final resData = await _serverHandler(req.data, reqCtx);

      if (ack == null) {
        return null;
      }

      final res = ProtoPayload({}, resData ?? ProtoMessageEmpty());

      res.setHeader(ProtoHeaderAuth(resClaim));
      res.setHeader(ProtoHeaderAck(ack.payloadId, ""));

      return res;
    } catch (e, stackTrace) {
      // TODO: use a logger instead
      print('request error $e; stack: \n$stackTrace');

      if (ack == null) {
        return null;
      }

      // for now always send full errors back
      return ProtoPayload.errorResponseWithStack(
        ack,
        e,
        stackTrace,
        auth: ProtoHeaderAuth(resClaim), // still sign on failures?
      );
    }
  }
}
