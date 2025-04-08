import 'dart:async';

import 'package:core/core.dart';
import 'package:core/device_keychain.dart';
import 'package:core/protocol.dart';
import 'package:core/src/rpc_client/exceptions.dart';
import 'package:core/src/rpc_client/transport.dart';
// import 'package:core/src/rpc_client/connection_status.dart';

/// [RpcClient] will perform network calls to [RpcServer]
/// In the future this will implement various pluggable transports such as
/// http, http2, websocket, etcetc...
/// TODO: this needs management of connection to various devices... for now its
/// only the server though
class RpcClient {
  // PluggableTransport is StreamChannel<Uint8List>
  final RpcClientTransport _transport;
  final DeviceKeychain _deviceKeychain;
  final Map<int, Completer<ProtoPayload>> _pendingRequests;

  // not thread safe!
  int _lastReqId = 0;

  RpcClient(this._transport, this._deviceKeychain) : _pendingRequests = {};

  // this will connect (or reconnect) the transport to the server
  // TODO: this needs lots of work to deal with broken sockets and timeouts of
  // ping/pong
  Future<void> connect(Uri uri) async {
    await _transport.connect(uri);

    _transport.stream.listen(
      (data) {
        //
        final payload = ProtoPayload.unpack(data);

        final ack = payload.getAck();
        if (ack == null) {
          // throwing here is not good?
          throw Exception('Ack must not be null on responses');
        }

        final resId = ack.payloadId;

        final pending = _pendingRequests[resId];
        if (pending == null) {
          throw Exception('Pending request $resId does not exist');
        }

        pending.complete(payload);
        _pendingRequests.remove(resId);
      },
      onError: (err, stack) {
        // TODO
        print('transport stream threw error $err');
        print(stack);
      },
      onDone: () {
        // do we need to close outserves?
      },
    );
  }

  Future<void> disconnect() async {
    await _transport.disconnect();
  }

  DeviceId serverDeviceId() {
    return _deviceKeychain.firstServerId();
  }

  Future<void> _send(
    DeviceId deviceId,
    ProtoAnyMessage data, {
    Completer<ProtoPayload>? responseCompleter,
  }) async {
    final payload = ProtoPayload({}, data);

    final authClaim = await _deviceKeychain.makeClaim(deviceId);
    payload.setHeader(ProtoHeaderAuth(authClaim));

    if (responseCompleter == null) {
      // just push the value out
      final binary = payload.pack();
      _transport.sink.add(binary);
      return;
    }

    final reqId = _lastReqId;
    _lastReqId++;

    payload.setHeader(ProtoHeaderAck(reqId, ""));
    final binary = payload.pack();

    _transport.sink.add(binary);

    _pendingRequests[reqId] = responseCompleter;
  }

  Future<T> _sendWithResponse<T extends ProtoAnyMessage>(
    DeviceId deviceId,
    ProtoAnyMessage data,
  ) async {
    final completer = Completer<ProtoPayload>();

    await _send(deviceId, data, responseCompleter: completer);

    final response = await completer.future;

    // ack is ensured to not be null when recieving a message
    final ack = response.getAck()!;

    if (ack.error.isNotEmpty) {
      throw RpcException(ack.error);
    }
    if (response.data is! T) {
      throw Exception(
        'Bad response data type. Expected "${T.runtimeType}", got "${response.data.runtimeType}"',
      );
    }

    return response.data as T;
  }

  Future<void> ping(DeviceId deviceId) async {
    await _sendWithResponse<ProtoMessageEmpty>(deviceId, ProtoMessagePing());
  }

  Future<void> uploadEvents(
    DeviceId deviceId,
    ProtoMessageEventValue data,
  ) async {
    await _sendWithResponse<ProtoMessageEmpty>(deviceId, data);
  }

  Future<ProtoMessageClockValue> queryClock(DeviceId deviceId) async {
    return await _sendWithResponse<ProtoMessageClockValue>(
      deviceId,
      ProtoMessageClockQuery(),
    );
  }

  Future<ProtoMessageEventValue> queryEvents(
    DeviceId deviceId,
    ProtoMessageEventQuery data,
  ) async {
    return await _sendWithResponse<ProtoMessageEventValue>(deviceId, data);
  }
}
