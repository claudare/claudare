import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/device_keychain.dart';
import 'package:core/protocol.dart';
import 'package:core/src/rpc_client/exceptions.dart';
import 'package:core/src/rpc_client/transport.dart';
import 'package:core/src/utils/retry_strategy.dart';

/// [RpcClient] will perform network calls to [RpcServer]
/// In the future this will implement various pluggable transports such as
/// http, http2, websocket, etcetc...
/// TODO: needs lots of work to deal with broken sockets and ping/pong
/// TODO: transport can break at any time. Need automatic reconnection and
/// a separate notification of failures
/// TODO: management of connection to multiple devices. for now its
/// only a single connection to the sync server
class RpcClient {
  static const int _maxRetries = 3;

  // PluggableTransport is StreamChannel<Uint8List>
  final RpcClientTransport _transport;
  final DeviceKeychain _deviceKeychain;
  final Map<int, Completer<ProtoPayload>> _pendingRequests;

  final RetryStrategy _retryStrategy = RetryStrategyConstantBackoff(
    duration: Duration(seconds: 3),
  );

  // not thread safe!
  int _lastReqId = 0;

  RpcClient(this._transport, this._deviceKeychain) : _pendingRequests = {};

  // [RpcClient] will keep connection status as connected until it fails
  // to reconnect a couple times

  Future<void> connect(Uri uri) async {
    await _tryConnect(uri);

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
        // this is where errors are propogated
        // when error happens, the pending requests will grow and "leak" memory
        // this is what is called when the connection cannot be established
        print('transport stream threw error $err');
        print(stack);
      },
      onDone: () {
        // do we need to close outserves?
      },
    );
  }

  Future<void> _tryConnect(Uri uri) async {
    int attemptIndex = 0;

    while (true) {
      try {
        final timeout = _retryStrategy.getTimeout(attemptIndex);
        await Future.delayed(timeout);

        if (_transport.connectionStatus !=
            RpcClientConnectionStatus.disconnected) {
          throw Exception(
            'Cannot start connection as status is ${_transport.connectionStatus}',
          );
        }
        await _transport.connect(uri);
        return;
      } catch (e) {
        print(
          'connection could be established. Try $attemptIndex, max $_maxRetries: $e',
        );
        attemptIndex++;
        if (attemptIndex > _maxRetries) {
          throw Exception('failed to connect to $uri: $e');
        }
      }
    }
  }

  Future<void> disconnect() async {
    if (_transport.connectionStatus == RpcClientConnectionStatus.disconnected) {
      throw Exception('Cannot disconnect as already disconnected');
    }

    try {
      await _transport.disconnect();
    } finally {
      // cleanup pending requests
      // TODO: this needs testing
      for (final completer in _pendingRequests.values) {
        completer.completeError(Exception('client disconnected'));
      }
      _pendingRequests.clear();
    }
  }

  RpcClientConnectionStatus get connectionStatus => _transport.connectionStatus;

  Stream<RpcClientConnectionStatus> get connectionStatusStream =>
      _transport.connectionStatusStream;

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

  Future<void> ping(DeviceId deviceId) {
    return _sendWithResponse<ProtoMessageEmpty>(deviceId, ProtoMessagePing());
  }

  Future<ProtoMessageClockValue> queryClock(DeviceId deviceId) {
    return _sendWithResponse<ProtoMessageClockValue>(
      deviceId,
      ProtoMessageClockQuery(),
    );
  }

  Future<ProtoMessageEventValue> queryEvents(
    DeviceId deviceId,
    ProtoMessageEventQuery data,
  ) {
    return _sendWithResponse<ProtoMessageEventValue>(deviceId, data);
  }

  Future<void> uploadEvents(DeviceId deviceId, ProtoMessageEventValue data) {
    return _sendWithResponse<ProtoMessageEmpty>(deviceId, data);
  }
}
